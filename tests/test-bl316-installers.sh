#!/usr/bin/env bash
# tests/test-bl316-installers.sh
#
# `## BL-316:` two installers that could never work.
#   1. Superpowers. The tool matrix (and README) gave `claude plugins add
#      superpowers`; Claude Code has no `add` verb (`claude plugin --help` lists
#      install|i). `# BL-284-PLUGIN-VERB` fixed only verify-install.sh's own fixer.
#   2. gitleaks on Linux. The matrix's linux_* rows were `GITLEAKS_VERSION=$(curl
#      …)` + `curl … | sudo tar …`. verify-install.sh's install path refuses that
#      (`$(` and `|`), and the eval readers that did run it installed an
#      unpinned, unverified, x64-only binary.
#
# The chain under test is the real one: REAL matrix -> REAL resolver -> each REAL
# reader, with every system tool stubbed on PATH (claude, curl, sudo, tar, uname,
# brew, apt). Nothing is downloaded and nothing is installed.
#   S  every reader runs the BL-284 Superpowers command; nothing live says `add`.
#   G  scripts/install-gitleaks.sh: pinned version, per-arch pinned SHA-256, the
#      check BEFORE the install, refusal on mismatch / unknown arch / non-Linux /
#      missing verifier.
#   V  verify-install.sh takes both through its STRUCTURED layer (so they work
#      under VERIFY_INSTALL_NO_LEGACY_DISPATCH=1) and still refuses lookalikes.
#   C  the eval readers (init.sh, upgrade-project.sh, adoption) find the installer
#      from any working directory (`# BL-316-SCRIPTS-DIR`).
#   M  every BL-316 marker is mutation-proven against a mirror; the tree under
#      test is never edited. Each mutant asserts it LANDED by literal text.
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

BL284_CMD='claude plugin install --scope user superpowers@claude-plugins-official'
GL_CMD='bash "${SOLO_SCRIPTS_DIR:-scripts}/install-gitleaks.sh"'
GL_URL_BASE='https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_'

# ── Host tools, isolated. jq is linked in by itself: its own directory may also
# hold a real gitleaks, brew or claude, and any of those would leak past a stub.
HOSTBIN="$TOPTMP/hostbin"; mkdir -p "$HOSTBIN"
ln -s "$(command -v jq)" "$HOSTBIN/jq"
REAL_TAR="$(command -v tar)"
SAFE_PATH_TAIL="$HOSTBIN:/usr/bin:/bin"

# ── Stubs. STUB_LOG records every call; nothing here touches the network or
# writes outside the fixture.
STUBS="$TOPTMP/stubs"; STUBS_UNAME="$TOPTMP/stubs-uname"
mkdir -p "$STUBS" "$STUBS_UNAME"
# `claude` mirrors the real dispatch (measured, 2.1.285): plugin|plugins is one
# group, the group validates its VERB first, and `add` is not one.
cat > "$STUBS/claude" <<'EOF'
#!/bin/sh
echo "claude $*" >> "${STUB_LOG:-/dev/null}"
case "${1:-}" in plugin|plugins) ;; *) echo "stub: unexpected group '${1:-}'" >&2; exit 2 ;; esac
case "${2:-}" in install|i) exit 0 ;; *) echo "error: unknown command '${2:-}'" >&2; exit 1 ;; esac
EOF
cat > "$STUBS/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >> "${STUB_LOG:-/dev/null}"
out=""; url=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"; url="$a"
done
case "$url" in
  https://github.com/gitleaks/gitleaks/releases/download/*.tar.gz)
    if [ -n "$out" ] && [ -n "${STUB_TARBALL:-}" ]; then cp "$STUB_TARBALL" "$out" && exit 0; fi ;;
esac
exit 22
EOF
cat > "$STUBS/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >> "${STUB_LOG:-/dev/null}"
if [ "${1:-}" = "install" ] && [ -n "${STUB_INSTALL_DIR:-}" ]; then
  src=""; dest=""
  for a in "$@"; do src="$dest"; dest="$a"; done
  cp "$src" "$STUB_INSTALL_DIR/$(basename "$dest")"
fi
exit 0
EOF
printf '#!/bin/sh\necho "tar $*" >> "${STUB_LOG:-/dev/null}"\nexec %s "$@"\n' "$REAL_TAR" > "$STUBS/tar"
for t in brew apt; do
  printf '#!/bin/sh\necho "%s $*" >> "${STUB_LOG:-/dev/null}"\nexit 0\n' "$t" > "$STUBS/$t"
done
cat > "$STUBS_UNAME/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -m) echo "${STUB_UNAME_M:-x86_64}" ;;
  *)  echo "${STUB_UNAME_S:-Linux}" ;;
esac
EOF
chmod +x "$STUBS"/* "$STUBS_UNAME"/*

# ── A fixture release tarball: a fake `gitleaks`, and its real SHA-256.
FIX_TGZ_DIR="$TOPTMP/tgz"; mkdir -p "$FIX_TGZ_DIR/src"
printf '#!/bin/sh\necho fake-gitleaks-bl316\n' > "$FIX_TGZ_DIR/src/gitleaks"
"$REAL_TAR" -czf "$FIX_TGZ_DIR/fixture.tar.gz" -C "$FIX_TGZ_DIR/src" gitleaks
FIX_SHA="$( { sha256sum "$FIX_TGZ_DIR/fixture.tar.gz" 2>/dev/null || shasum -a 256 "$FIX_TGZ_DIR/fixture.tar.gz"; } | awk '{print $1; exit}')"

# ── Shared helpers ───────────────────────────────────────────────────────────
CASE_DETAIL=""

# bl284_cmd_of <root> — the one `claude …` line inside fix_superpowers.
bl284_cmd_of() {
  awk '/^fix_superpowers\(\) \{/{f=1; next} f && /^\}/{exit} f' "$1/scripts/verify-install.sh" \
    | command grep -E '^[[:space:]]*claude ' | sed 's/^[[:space:]]*//'
}

# resolver_out <root> <devos> — print the REAL resolver's JSON for a host with
# brew (darwin) or apt (linux), no gitleaks, and no Superpowers. Cached per root.
resolver_out() {
  local root="$1" devos="$2" key f home
  key="$(printf '%s' "$root" | cksum | awk '{print $1}')"
  f="$TOPTMP/res-$key-$devos.json"
  if [ ! -s "$f" ]; then
    home="$TOPTMP/res-home"; mkdir -p "$home"
    env -u CLAUDE_CONFIG_DIR -u SOLO_SCRIPTS_DIR HOME="$home" PATH="$STUBS:$SAFE_PATH_TAIL" \
      RESOLVE_TOOLS_EVAL_TIMEOUT=3 \
      bash "$root/scripts/resolve-tools.sh" --dev-os "$devos" --platform web \
        --language typescript --track standard --phase 2 \
        --matrix-dir "$root/templates/tool-matrix" > "$f" 2>/dev/null || : > "$f"
  fi
  cat "$f"
}

# payload_for <root> <devos> <name>... — resolver output narrowed to the named
# auto_install rows (in matrix order). Every other row is dropped so that no
# reader under test is ever handed a command this suite has not stubbed.
payload_for() {
  local root="$1" devos="$2"; shift 2
  resolver_out "$root" "$devos" | jq -c --args '
    {auto_install: [.auto_install[] | select(.name as $n | $ARGS.positional | index($n))],
     manual_install: [], already_installed: [], deferred: []}' "$@" 2>/dev/null
}

# pin_of <file> <X64|ARM64>
pin_of() { sed -n "s/^GITLEAKS_SHA256_LINUX_$2=\"\([0-9a-f]*\)\".*/\1/p" "$1" 2>/dev/null; }

# installer_copy <root> <dest-dir> <none|x64|arm64|alone>
#   Copies the installer (+ verifier, unless `alone`) and, for x64/arm64,
#   replaces THAT arch's real pin — and only that one — with the fixture's hash.
installer_copy() {
  local root="$1" dest="$2" which="$3" f old new_line
  mkdir -p "$dest" || return 1
  cp "$root/scripts/install-gitleaks.sh" "$dest/" 2>/dev/null || return 1
  [ "$which" = "alone" ] || cp "$root/scripts/ci-verify-sha256.sh" "$dest/" || return 1
  f="$dest/install-gitleaks.sh"
  case "$which" in
    x64|arm64)
      local arch_u; arch_u="$(printf '%s' "$which" | tr '[:lower:]' '[:upper:]')"
      old="$(pin_of "$f" "$arch_u")"
      [ -n "$old" ] || return 1
      new_line="GITLEAKS_SHA256_LINUX_${arch_u}=\"$FIX_SHA\""
      OLD="GITLEAKS_SHA256_LINUX_${arch_u}=\"$old\"" NEW="$new_line" awk '
        $0 == ENVIRON["OLD"] { print ENVIRON["NEW"]; next } { print }' "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
      # LANDED, by literal text: the fixture pin is there once and the real one is gone.
      [ "$(command grep -cxF "$new_line" "$f")" = "1" ] || return 1
      ! command grep -qF "$old" "$f" || return 1
      ;;
  esac
  return 0
}

# run_installer <scripts-dir> <uname -s> <uname -m> — sets RI_RC, RI_OUT, RI_LOG, RI_INST
run_installer() {
  local d="$1" s="$2" m="$3" fx
  fx="$(newtmp)"; RI_LOG="$fx/log"; RI_INST="$fx/installed"; mkdir -p "$RI_INST"; : > "$RI_LOG"
  RI_RC=0
  RI_OUT="$( cd "$fx" && env PATH="$STUBS_UNAME:$STUBS:$SAFE_PATH_TAIL" STUB_LOG="$RI_LOG" \
      STUB_TARBALL="$FIX_TGZ_DIR/fixture.tar.gz" STUB_INSTALL_DIR="$RI_INST" \
      STUB_UNAME_S="$s" STUB_UNAME_M="$m" bash "$d/install-gitleaks.sh" 2>&1 )" || RI_RC=$?
}

# canary_fw <dir> <payload> — a fixture framework root: a resolver stub that
# prints <payload>, and an install-gitleaks.sh that only records that it ran.
canary_fw() {
  local fw="$1" payload="$2"
  mkdir -p "$fw/scripts" "$fw/templates/tool-matrix" || return 1
  { printf '#!/usr/bin/env bash\ncat <<'"'"'RESOLVERJSON'"'"'\n'; printf '%s\n' "$payload"; printf 'RESOLVERJSON\n'; } > "$fw/scripts/resolve-tools.sh"
  printf '#!/usr/bin/env bash\nprintf "ran\\n" >> %s\n' "'$fw/CANARY'" > "$fw/scripts/install-gitleaks.sh"
  chmod +x "$fw/scripts/resolve-tools.sh" "$fw/scripts/install-gitleaks.sh"
}

# vi_extract <root> <out> — verify-install.sh's install machinery + fix_superpowers.
vi_extract() {
  local vi="$1/scripts/verify-install.sh"
  {
    awk '/^_TOOL_INSTALL_ALLOWED_HEADS=\(/ {flag=1} flag {print}
         flag && /^fix_tool_install\(\) \{/ {f=1}
         f && /^\}$/ {flag=0; f=0; exit}' "$vi"
    awk '/^fix_superpowers\(\) \{/{f=1} f{print} f && /^\}$/{exit}' "$vi"
  } > "$2"
}

# run_vi <root> <scripts-dir-for-SCRIPT_DIR> <payload> [NO_LEGACY] — sets VI_RC, VI_OUT, VI_LOG, VI_INST
run_vi() {
  local root="$1" sd="$2" payload="$3" nolegacy="${4:-0}" fx
  fx="$(newtmp)"; VI_LOG="$fx/log"; VI_INST="$fx/installed"; mkdir -p "$VI_INST"; : > "$VI_LOG"
  vi_extract "$root" "$fx/extract.sh"
  VI_OUT="$( cd "$fx" && env -u SOLO_SCRIPTS_DIR PATH="$STUBS_UNAME:$STUBS:$SAFE_PATH_TAIL" \
      STUB_LOG="$VI_LOG" STUB_TARBALL="$FIX_TGZ_DIR/fixture.tar.gz" STUB_INSTALL_DIR="$VI_INST" \
      STUB_UNAME_S=Linux STUB_UNAME_M=x86_64 VERIFY_INSTALL_NO_LEGACY_DISPATCH="$nolegacy" \
      _E="$fx/extract.sh" _P="$payload" _SD="$sd" bash -c '
        set +e
        print_info() { echo "[INFO] $*" >&2; }; print_warn() { echo "[WARN] $*" >&2; }
        print_fail() { echo "[FAIL] $*" >&2; }; print_ok() { echo "[OK] $*" >&2; }
        source "$_E"
        SCRIPT_DIR="$_SD"; RESOLVER_OUTPUT="$_P"
        fix_tool_install 0; echo "RC=$?" >&2' 2>&1 )"
  VI_RC="$(printf '%s\n' "$VI_OUT" | sed -n 's/^RC=//p' | tail -1)"
}

# ════════════════════════════════════════════════════════════════════════════
# CASES — each takes the framework root under test, returns 0 (pass) / 1 (fail)
# and leaves its evidence in CASE_DETAIL, so the mutants can re-run it.
# ════════════════════════════════════════════════════════════════════════════

case_S0() {   # the BL-284 fixer runs exactly the expected command
  local got; got="$(bl284_cmd_of "$1")"
  CASE_DETAIL="fix_superpowers runs: '$got'"
  [ "$got" = "$BL284_CMD" ]
}

case_S1() {   # every Superpowers install value in every matrix file IS that command
  local n bad
  n="$(jq -s '[.[].tools[]? | select(.name=="Superpowers") | .install | to_entries[] | select(.key != "manual")] | length' "$1"/templates/tool-matrix/*.json)"
  bad="$(jq -rs --arg c "$BL284_CMD" '[.[].tools[]? | select(.name=="Superpowers") | .install | to_entries[] | select(.key != "manual") | select(.value != $c) | "\(.key)=\(.value|tojson)"] | join("; ")' "$1"/templates/tool-matrix/*.json)"
  CASE_DETAIL="keys=$n mismatches=[${bad}]"
  [ "${n:-0}" -ge 3 ] && [ -z "$bad" ]
}

case_S2() {   # nothing live ships `claude plugins add` / `claude plugin add`
  local hits
  hits="$( cd "$1" && command grep -rnE 'claude plugins? add' README.md CONTRIBUTING.md CLAUDE.md init.sh templates scripts docs evaluation-prompts 2>/dev/null \
    | command grep -vE '^docs/(superpowers/[^/]+/archive|handoffs|designs)/' \
    | command grep -vE '^(scripts/[^:]*|init\.sh):[0-9]+:[[:space:]]*#' )"
  CASE_DETAIL="live hits: ${hits:-none}"
  [ -z "$hits" ]
}

case_S3() {   # README's Superpowers row shows the same command
  local row; row="$(command grep -F '| **Superpowers** |' "$1/README.md")"
  CASE_DETAIL="row: $row"
  printf '%s' "$row" | command grep -qF "\`$BL284_CMD\`"
}

case_S4() {   # the real resolver hands that command to every reader, darwin and linux
  local d l
  d="$(payload_for "$1" darwin Superpowers | jq -c '.auto_install[0] | [.install_cmd, .install_cmds]')"
  l="$(payload_for "$1" linux Superpowers | jq -c '.auto_install[0] | [.install_cmd, .install_cmds]')"
  local want; want="$(jq -cn --arg c "$BL284_CMD" '[$c, [$c]]')"
  CASE_DETAIL="darwin=$d linux=$l"
  [ "$d" = "$want" ] && [ "$l" = "$want" ]
}

case_S5() {   # verify-install's matrix row runs it STRUCTURED (fix_superpowers), not via bash -c
  local p; p="$(payload_for "$1" darwin Superpowers)"
  local ok=0 mode
  for mode in 0 1; do
    run_vi "$1" "$1/scripts" "$p" "$mode"
    CASE_DETAIL="NO_LEGACY=$mode rc=$VI_RC calls=[$(tr '\n' ';' < "$VI_LOG")] out=$(printf '%s' "$VI_OUT" | tr '\n' ' ' | cut -c1-300)"
    [ "$VI_RC" = "0" ] || return 1
    [ "$(cat "$VI_LOG")" = "$BL284_CMD" ] || return 1   # the stub logs `claude <argv>`, i.e. the command itself
    printf '%s' "$VI_OUT" | command grep -q 'DEPRECATED' && return 1
    ok=$((ok + 1))
  done
  [ "$ok" -eq 2 ]
}

case_G0() {   # matrix: brew on macOS; the vetted installer on every Linux key
  local brew bad
  brew="$(jq -r '.tools[] | select(.name=="gitleaks") | .install.darwin_brew' "$1/templates/tool-matrix/common.json")"
  bad="$(jq -r --arg c "$GL_CMD" '.tools[] | select(.name=="gitleaks") | .install | [ "linux_apt","linux_dnf","linux_pacman" ][] as $k | select(.[$k] != $c) | $k' "$1/templates/tool-matrix/common.json" 2>/dev/null | tr '\n' ' ')"
  CASE_DETAIL="darwin_brew='$brew' linux keys not the installer: [${bad}]"
  [ "$brew" = "brew install gitleaks" ] && [ -z "$bad" ]
}

case_G1() {   # the real linux resolver emits exactly that one stage
  local got want
  got="$(payload_for "$1" linux gitleaks | jq -c '.auto_install[0] | [.install_cmd, .install_cmds]')"
  want="$(jq -cn --arg c "$GL_CMD" '[$c, [$c]]')"
  CASE_DETAIL="got=$got"
  [ "$got" = "$want" ]
}

case_G2() {   # the pins: CI's version and x64 digest, a distinct well-formed arm64 digest
  local f="$1/scripts/install-gitleaks.sh" wf="$1/.github/workflows/tests.yml" v x a civ cix
  v="$(sed -n 's/^GITLEAKS_VERSION="\([^"]*\)".*/\1/p' "$f" 2>/dev/null)"
  x="$(pin_of "$f" X64)"; a="$(pin_of "$f" ARM64)"
  civ="$(awk -F'"' '/GITLEAKS_VERSION:/{print $2}' "$wf" | sort -u)"
  cix="$(awk -F'"' '/GITLEAKS_SHA256:/{print $2}' "$wf" | sort -u)"
  CASE_DETAIL="installer v=$v x64=$x arm64=$a | tests.yml v=[$civ] x64=[$cix]"
  [ -n "$v" ] && [ "$v" = "$civ" ] && [ -n "$x" ] && [ "$x" = "$cix" ] || return 1
  case "$a" in ""|*[!0-9a-f]*) return 1 ;; esac
  [ "${#a}" -eq 64 ] && [ "$a" != "$x" ]
}

case_G3() {   # x86_64: downloads the x64 asset, verifies against the x64 pin, installs it
  local d; d="$(newtmp)/s"
  installer_copy "$1" "$d" x64 || { CASE_DETAIL="could not prepare a pin-rewritten copy"; return 1; }
  run_installer "$d" Linux x86_64
  CASE_DETAIL="rc=$RI_RC calls=[$(tr '\n' ';' < "$RI_LOG")] out=$(printf '%s' "$RI_OUT" | tr '\n' ' ')"
  [ "$RI_RC" -eq 0 ] && command grep -qF "${GL_URL_BASE}x64.tar.gz" "$RI_LOG" \
    && command grep -qE '^sudo install -m 0755 .*/gitleaks /usr/local/bin/gitleaks$' "$RI_LOG" \
    && cmp -s "$RI_INST/gitleaks" "$FIX_TGZ_DIR/src/gitleaks"
}

case_G4() {   # aarch64: the arm64 asset against the ARM64 pin (the x64 pin stays real)
  local d; d="$(newtmp)/s"
  installer_copy "$1" "$d" arm64 || { CASE_DETAIL="could not prepare a pin-rewritten copy"; return 1; }
  run_installer "$d" Linux aarch64
  CASE_DETAIL="rc=$RI_RC calls=[$(tr '\n' ';' < "$RI_LOG")] out=$(printf '%s' "$RI_OUT" | tr '\n' ' ')"
  [ "$RI_RC" -eq 0 ] && command grep -qF "${GL_URL_BASE}arm64.tar.gz" "$RI_LOG" \
    && ! command grep -qF "${GL_URL_BASE}x64" "$RI_LOG" \
    && cmp -s "$RI_INST/gitleaks" "$FIX_TGZ_DIR/src/gitleaks"
}

case_G5() {   # an unpinned machine type is refused before any download
  local d; d="$(newtmp)/s"
  installer_copy "$1" "$d" none || { CASE_DETAIL="no installer to copy"; return 1; }
  run_installer "$d" Linux armv7l
  CASE_DETAIL="rc=$RI_RC calls=[$(tr '\n' ';' < "$RI_LOG")] out=$(printf '%s' "$RI_OUT" | tr '\n' ' ')"
  [ "$RI_RC" -ne 0 ] && [ ! -s "$RI_LOG" ] \
    && printf '%s' "$RI_OUT" | command grep -qF 'Install gitleaks yourself: https://github.com/gitleaks/gitleaks/releases'
}

case_G6() {   # a non-Linux host is refused (and pointed at brew) before any download
  local d; d="$(newtmp)/s"
  installer_copy "$1" "$d" none || { CASE_DETAIL="no installer to copy"; return 1; }
  run_installer "$d" Darwin arm64
  CASE_DETAIL="rc=$RI_RC calls=[$(tr '\n' ';' < "$RI_LOG")] out=$(printf '%s' "$RI_OUT" | tr '\n' ' ')"
  [ "$RI_RC" -ne 0 ] && [ ! -s "$RI_LOG" ] && printf '%s' "$RI_OUT" | command grep -qF 'brew install gitleaks'
}

case_G7() {   # the UNMODIFIED installer refuses a tarball that is not the pinned one
  local d; d="$(newtmp)/s"
  installer_copy "$1" "$d" none || { CASE_DETAIL="no installer to copy"; return 1; }
  run_installer "$d" Linux x86_64
  CASE_DETAIL="rc=$RI_RC calls=[$(tr '\n' ';' < "$RI_LOG")] installed=[$(ls "$RI_INST" | tr '\n' ' ')] out=$(printf '%s' "$RI_OUT" | tr '\n' ' ')"
  [ "$RI_RC" -ne 0 ] && command grep -qF "${GL_URL_BASE}x64.tar.gz" "$RI_LOG" \
    && ! command grep -q '^sudo' "$RI_LOG" && [ -z "$(ls "$RI_INST")" ] \
    && printf '%s' "$RI_OUT" | command grep -qF 'did not match its pinned SHA-256'
}

case_G8() {   # no verifier beside it: refused, and nothing is even downloaded
  local d; d="$(newtmp)/s"
  installer_copy "$1" "$d" alone || { CASE_DETAIL="no installer to copy"; return 1; }
  run_installer "$d" Linux x86_64
  CASE_DETAIL="rc=$RI_RC calls=[$(tr '\n' ';' < "$RI_LOG")] out=$(printf '%s' "$RI_OUT" | tr '\n' ' ')"
  [ "$RI_RC" -ne 0 ] && [ ! -s "$RI_LOG" ]
}

case_V1() {   # verify-install installs gitleaks on Linux — structured, so also under NO_LEGACY=1
  local p d mode; p="$(payload_for "$1" linux gitleaks)"
  d="$(newtmp)/scripts"
  installer_copy "$1" "$d" x64 || { CASE_DETAIL="could not prepare the installer beside verify-install"; return 1; }
  for mode in 0 1; do
    run_vi "$1" "$d" "$p" "$mode"
    CASE_DETAIL="NO_LEGACY=$mode rc=$VI_RC calls=[$(tr '\n' ';' < "$VI_LOG")] out=$(printf '%s' "$VI_OUT" | tr '\n' ' ' | cut -c1-400)"
    [ "$VI_RC" = "0" ] || return 1
    printf '%s' "$VI_OUT" | command grep -q 'REFUSED' && return 1
    cmp -s "$VI_INST/gitleaks" "$FIX_TGZ_DIR/src/gitleaks" || return 1
  done
  return 0
}

case_V2() {   # lookalikes of the vetted string are still refused, and nothing runs
  local d c p; d="$(newtmp)/scripts"
  installer_copy "$1" "$d" x64 || { CASE_DETAIL="could not prepare the installer"; return 1; }
  for c in "$GL_CMD && touch $d/CHAINED" "bash $d/install-gitleaks.sh" "bash \"\${SOLO_SCRIPTS_DIR:-scripts}/install-gitleaks.sh\" --x"; do
    p="$(jq -cn --arg c "$c" '{auto_install:[{name:"gitleaks",category:"x",install_cmd:$c,install_cmds:[$c],required:true,description:"x"}]}')"
    run_vi "$1" "$d" "$p" 0
    CASE_DETAIL="cmd=[$c] rc=$VI_RC calls=[$(tr '\n' ';' < "$VI_LOG")]"
    [ "$VI_RC" != "0" ] || return 1
    [ ! -e "$d/CHAINED" ] && [ ! -s "$VI_LOG" ] || return 1
    printf '%s' "$VI_OUT" | command grep -q 'REFUSED' || return 1
  done
  return 0
}

case_V3() {   # the vetted string with no installer beside verify-install: refused, says why
  local p d; p="$(payload_for "$1" linux gitleaks)"; d="$(newtmp)/empty-scripts"; mkdir -p "$d"
  run_vi "$1" "$d" "$p" 0
  CASE_DETAIL="rc=$VI_RC out=$(printf '%s' "$VI_OUT" | tr '\n' ' ' | cut -c1-300)"
  [ "$VI_RC" != "0" ] && printf '%s' "$VI_OUT" | command grep -qF 'not beside verify-install.sh'
}

case_C1() {   # init.sh — from a directory with no scripts/ — runs the installer and the BL-284 command
  local p fw cwd log out
  p="$(payload_for "$1" linux gitleaks Superpowers)"
  fw="$(newtmp)/fw"; canary_fw "$fw" "$p" || { CASE_DETAIL="fixture"; return 1; }
  cwd="$(newtmp)"; log="$cwd/log"; : > "$log"
  awk '/^resolve_and_install_tools\(\) \{/{f=1} f{print} f && /^\}$/{exit}' "$1/init.sh" > "$cwd/fn.sh"
  out="$( cd "$cwd" && env -u SOLO_SCRIPTS_DIR PATH="$STUBS:$SAFE_PATH_TAIL" STUB_LOG="$log" _FN="$cwd/fn.sh" _FW="$fw" bash -c '
      set +e
      print_step() { :; }; print_info() { :; }; print_ok() { echo "[OK] $*"; }; print_warn() { echo "[WARN] $*"; }; print_fail() { :; }
      BOLD=; NC=; GREEN=; CYAN=; BLUE=; YELLOW=; RED=
      SCRIPT_DIR="$_FW"; OS_TYPE=Linux; PLATFORM=web; LANGUAGE=typescript; TRACK=standard
      NON_INTERACTIVE=true; AUTO_INSTALL_TOOLS=Y
      is_qdrant_mcp_registered() { return 1; }; is_qdrant_container_running() { return 1; }
      source "$_FN"; resolve_and_install_tools' 2>&1 )"
  CASE_DETAIL="canary=$([ -s "$fw/CANARY" ] && echo ran || echo ABSENT) calls=[$(tr '\n' ';' < "$log")] out=$(printf '%s' "$out" | command grep -E 'WARN|OK' | tr '\n' ' ' | cut -c1-300)"
  [ -s "$fw/CANARY" ] && command grep -qxF "$BL284_CMD" "$log"
}

case_C2() {   # upgrade-project.sh's install loop — same, from a directory with no scripts/
  local p fw cwd log
  p="$(payload_for "$1" linux gitleaks Superpowers)"
  fw="$(newtmp)/fw"; canary_fw "$fw" "$p" || { CASE_DETAIL="fixture"; return 1; }
  cwd="$(newtmp)"; log="$cwd/log"; : > "$log"
  awk '/^upgrade_auto_install_from_resolver\(\) \{/{f=1} f{print} f && /^\}$/{exit}' "$1/scripts/upgrade-project.sh" > "$cwd/fn.sh"
  ( cd "$cwd" && env -u SOLO_SCRIPTS_DIR PATH="$STUBS:$SAFE_PATH_TAIL" STUB_LOG="$log" _FN="$cwd/fn.sh" _FW="$fw" \
      _HC="$1/scripts/lib/helpers-core.sh" _P="$p" bash -c '
      set +e
      source "$_HC"; source "$_FN"
      ORCHESTRATOR_ROOT="$_FW"
      upgrade_auto_install_from_resolver "$_P" "$(printf "%s" "$_P" | jq ".auto_install | length")"' ) >/dev/null 2>&1
  CASE_DETAIL="canary=$([ -s "$fw/CANARY" ] && echo ran || echo ABSENT) calls=[$(tr '\n' ';' < "$log")]"
  [ -s "$fw/CANARY" ] && command grep -qxF "$BL284_CMD" "$log"
}

# Adoption fixtures (mirrors tests/test-brownfield-wp10a-tool-resolution.sh).
ADOPT_REPORT=""
adopt_report() {
  [ -n "$ADOPT_REPORT" ] && return 0
  local t; t="$(newtmp)"
  mk_adoptee "$t/tpl" || return 1
  bash "$REPO_ROOT/scripts/scout.sh" --root "$t/tpl" --out "$t/scan" >/dev/null 2>&1 || return 1
  [ -s "$t/scan/scout-report.json" ] || return 1
  ADOPT_REPORT="$t/scan/scout-report.json"
}
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" && git init -q . && git config user.email "bl316@test.invalid" \
      && git config user.name "BL316 Test" && git config core.excludesFile /dev/null ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service and a postgres database.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add package.json README.md docs/product.md docs/architecture.md \
      && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
}
mk_mirror() {
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$1/README.md" "$2/" \
    && mkdir -p "$2/.github/workflows" && cp -p "$1/.github/workflows/tests.yml" "$2/.github/workflows/"
}

case_C3() {   # adoption's install arm (accepted) runs the framework's installer, not a cwd-relative path
  local root="$1" p m t
  adopt_report || { CASE_DETAIL="could not build a scout report"; return 1; }
  p="$(payload_for "$root" linux gitleaks)"
  t="$(newtmp)"; m="$t/fw"
  if [ "$root" = "$REPO_ROOT" ]; then mk_mirror "$root" "$m" || { CASE_DETAIL="mirror"; return 1; }
  else m="$root"; fi
  printf '#!/usr/bin/env bash\nprintf "ran\\n" >> %s\n' "'$t/CANARY'" > "$m/scripts/install-gitleaks.sh"
  { printf '#!/usr/bin/env bash\ncat <<'"'"'RESOLVERJSON'"'"'\n'; printf '%s\n' "$p"; printf 'RESOLVERJSON\n'; } > "$t/resolver"
  chmod +x "$t/resolver"
  mk_adoptee "$t/p" || { CASE_DETAIL="adoptee"; return 1; }
  printf '1\nstandard\n1\n1\n1\n1\n1\n' > "$t/answers"   # tier 1, track, SET IT UP NOW, four confirmations
  ( cd "$t/p" && env -u SOLO_SCRIPTS_DIR SOIF_ADOPT_RESOLVER="$t/resolver" PATH="$STUBS:$SAFE_PATH_TAIL" \
      bash "$m/scripts/adopt-project.sh" --scan-report "$ADOPT_REPORT" ) < "$t/answers" > "$t/out" 2>&1
  CASE_DETAIL="canary=$([ -s "$t/CANARY" ] && echo ran || echo ABSENT) offered=$(command grep -c 'This would run, exactly as written' "$t/out")"
  [ -s "$t/CANARY" ]
}

check() {   # check <label> <case-fn> — run against the tree under test
  local label="$1" fn="$2"
  if "$fn" "$REPO_ROOT"; then pass "$label"; else fail_ "$label" "$CASE_DETAIL"; fi
}

echo "=== S — Superpowers: one command, the BL-284 one, in every reader ==="
check "S0 — fix_superpowers (# BL-284-PLUGIN-VERB) runs '$BL284_CMD'" case_S0
check "S1 — every Superpowers install value in templates/tool-matrix/*.json is that command" case_S1
check "S2 — no live file ships 'claude plugins add' / 'claude plugin add'" case_S2
check "S3 — README's Superpowers row shows that command" case_S3
check "S4 — the real resolver emits it (install_cmd and install_cmds), darwin and linux" case_S4
check "S5 — verify-install's matrix row runs it via fix_superpowers: rc 0, no DEPRECATED path, also under NO_LEGACY=1" case_S5

echo "=== G — gitleaks on Linux: a pinned, checksum-verified installer ==="
check "G0 — matrix: darwin_brew stays 'brew install gitleaks'; linux_apt/dnf/pacman are the vetted installer" case_G0
check "G1 — the real linux resolver emits exactly that one stage" case_G1
check "G2 — pins: version and x64 digest equal tests.yml's; arm64 digest well-formed and distinct" case_G2
check "G3 — x86_64: x64 asset, verified, installed to /usr/local/bin/gitleaks" case_G3
check "G4 — aarch64: arm64 asset against the ARM64 pin" case_G4
check "G5 — armv7l: refused before any download, with the manual-install pointer" case_G5
check "G6 — Darwin: refused before any download, pointed at brew" case_G6
check "G7 — a tarball that is not the pinned one is REFUSED: nothing installed, sudo never called" case_G7
check "G8 — no verifier beside the installer: refused, nothing downloaded" case_G8

echo "=== V — verify-install.sh's install path ==="
check "V1 — gitleaks' Linux row is not refused and installs, also under NO_LEGACY=1 (structured layer)" case_V1
check "V2 — lookalikes (chained, other path, extra argument) are refused and nothing runs" case_V2
check "V3 — no installer beside verify-install.sh: refused, and the refusal says so" case_V3

echo "=== C — the eval readers find the installer from any working directory ==="
check "C1 — init.sh resolve_and_install_tools runs the installer and the BL-284 command" case_C1
check "C2 — upgrade-project.sh upgrade_auto_install_from_resolver does the same" case_C2
check "C3 — adoption's accepted install runs the framework's installer" case_C3

# ════════════════════════════════════════════════════════════════════════════
# M — MUTANTS. Each excises or rewrites ONE marked line in a mirror, asserts the
# edit landed by its literal text and still parses, and requires a named case
# to go RED against that mirror.
# ════════════════════════════════════════════════════════════════════════════
echo "=== M — every BL-316 marker is load-bearing ==="

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
    fail_ "$id" "$what — SURVIVED: $killer still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_}"
  fi
}

# A `case` arm cannot become `:`, so the two verify-install arms become a
# pattern that never matches.
NEVER='    __bl316_mutant_never_matches__) ;;'
mutant MV1 scripts/verify-install.sh '# BL-316-VETTED-INSTALLER' "$NEVER" case_V1 \
  "verify-install no longer recognises the vetted gitleaks installer"
mutant MV3 scripts/verify-install.sh '# BL-316-VETTED-INSTALLER' \
  "    'bash \"\${SOLO_SCRIPTS_DIR:-scripts}/install-gitleaks.sh\"'*) _vetted=\"install-gitleaks.sh\" ;;" case_V2 \
  "the vetted match becomes a prefix match, so a lookalike rides it"
mutant MV2 scripts/verify-install.sh '# BL-316-SUPERPOWERS-ROUTE' "$NEVER" case_S5 \
  "verify-install's Superpowers row falls back to the deprecated bash -c path"
mutant MI1 init.sh '# BL-316-SCRIPTS-DIR' ':' case_C1 \
  "init.sh stops exporting SOLO_SCRIPTS_DIR"
mutant MU1 scripts/upgrade-project.sh '# BL-316-SCRIPTS-DIR' ':' case_C2 \
  "upgrade-project.sh stops exporting SOLO_SCRIPTS_DIR"
mutant MA1 scripts/lib/adopt/adopt-tools.sh '# BL-316-SCRIPTS-DIR' ':' case_C3 \
  "adoption's install subshell stops exporting SOLO_SCRIPTS_DIR"
mutant MG1 scripts/install-gitleaks.sh '# BL-316-CHECKSUM' ':' case_G7 \
  "the checksum check is removed"
mutant MG2 scripts/install-gitleaks.sh '# BL-316-ARCH-ARM64' \
  '  aarch64|arm64) asset_arch="arm64"; sha="$GITLEAKS_SHA256_LINUX_X64" ;;' case_G4 \
  "aarch64 is verified against the x64 pin"
mutant MG3 scripts/install-gitleaks.sh '# BL-316-ARCH-X64' \
  '  x86_64|amd64)  asset_arch="x64";   sha="$GITLEAKS_SHA256_LINUX_ARM64" ;;' case_G3 \
  "x86_64 is verified against the arm64 pin"
mutant MG4 scripts/install-gitleaks.sh '# BL-316-ARCH-OTHER' \
  '  *) asset_arch="x64"; sha="$GITLEAKS_SHA256_LINUX_X64" ;;' case_G5 \
  "an unpinned machine type silently gets the x64 asset"
mutant MG5 scripts/install-gitleaks.sh '# BL-316-VERIFIER-PRESENT' ':' case_G8 \
  "the verifier-presence check before the download is removed"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
