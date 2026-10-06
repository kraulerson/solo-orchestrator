#!/usr/bin/env bash
# tests/test-bl318-g4g6.sh — `## BL-318:` G6 (three small fixes) and the doc
# claims of G4 that a script can check. Dogfood run 2 (k-pdf, 2026-10-03),
# findings 5, 12, 19 (G6) and 27, 20, 21, 26, 2, 14 (G4).
#
# WHAT EACH CASE OWNS.
#   D*  G6(a): the deploy detectors — Scout's `deploy-around-the-release-lane`
#       and adoption's `deploy-on-push` — do not count "deploy" inside a
#       command-line flag (`--no-deployment-flag`), and still count a real
#       deploy step (`# BL-318-G6-DEPLOY-FLAG`, `# BL-318-G6-DEPLOY-FLAG-SCOUT`).
#       D1  k-pdf's real ci.yml, from dogfood run 2's git bundle at 0bb0465:
#           neither detector fires, and a real Scout of that commit lists no
#           finding for it. LOCAL ONLY: it SKIPS where the bundle is absent (CI
#           has none, and the repository it came from is private).
#       D2  the same shape written here — Nuitka's flag on a line of its own in
#           a bash array — and three more flag spellings: neither fires.
#       D3  fifteen real deploy steps, one workflow each: both fire on every one.
#           Review round 1 added eight: a flag BEFORE the deploy word on the same
#           line (R-1: netlify, kubectl, rsync), a deploy glued to a flag by `;`
#           (the final check's N-1: `make --quiet;./deploy.sh`, whose word
#           follows the `;` itself, so only `;` ends that flag), a flag's `=value`
#           that names the deploy (R-2: ansible `--tags=deploy`, nx
#           `--target=deploy`), a deploy glued to a flag by `&&` (R-2), and a
#           flag whose whole name is `deploy` (`./scripts/ci.sh --deploy`).
#       D4  adoption reports the deploy STEP's line, not an earlier flag's.
#       D5  the two detectors' flag rules stay byte-identical (review round 1,
#           R-7): the strip pattern and the whole-name pattern, each read off
#           its marker line in both files.
#   B*  G6(b): a refusal says "nothing was written to this project", and when
#       the run registered an MCP server with Claude Code it says so, by name,
#       with the commands to see and remove it (`# BL-318-G6-OUTSIDE`).
#       B1  the dogfood shape, a whole adoption: "set it up now" registers both
#           servers, then the next mandatory question gets no answer. Its CI
#           section reads D2's shape as clean (G6(a) end to end).
#       B2  skip: nothing registered, so the refusal names nothing outside.
#       B3  the registration commands fail: the receipt shows nothing, so the
#           refusal claims nothing.
#       B4  Context7 was registered BEFORE the run: only Qdrant is named.
#       B5  a BLOCKED refusal (the run had touched the project) names it too.
#       B6  a forced block (`adopt_block`, the `# BL-242-REFUSE-AFTER-COMMIT`
#           arm) after a registration names it too (review round 1, R-4).
#       Since review round 1 (R-6) a stop after a registration is labelled
#       [BLOCKED], not [REFUSED]: the run had begun (`# BL-318-G6-BLOCK-LABEL`).
#   C*  G6(c): wording only — "the commit adoption started from", never "the
#       commit this project was adopted at" (`adoptedAtCommit` is the
#       PRE-ADOPTION tip by design, scripts/lib/adoption-stamp.sh).
#       C1  no shipped script and no user doc says "was adopted at".
#       C2  the finisher's check, run: a record naming another commit is
#           refused in the new words.
#   P*  G4: doc claims a script can check.
#       P1  docs/adoption.md "What you need" names Superpowers with the exact
#           install command — the tool matrix's own — and quotes the block a
#           session prints without it.
#       P2  ONE prerequisites list for adoption: README's adoption section and
#           its Prerequisites section both link to adoption.md's "What you
#           need", and the adoption section names no tool itself.
#       P3  README lists Superpowers under Prerequisites, not as optional.
#       P4  every Guardrails message the docs quote is in the Guardrails hooks
#           (needs the clone at ~/.claude-dev-framework; SKIPS without it).
#       P5  the session-start guidance names each kind of message, and each is
#           text the session-start scripts really print.
#       P6  the phase-0 paragraph cites `check_commit_ready`, which lets every
#           commit through below phase 2.
#       P7  the override says to clear the recorded question first, with a
#           command pending-approval.sh has (review round 1, R-3: Solo's own
#           check blocks every commit while .claude/pending-approval.json exists).
#       P8  no doc calls Superpowers optional, init.sh does not call it
#           "recommended", and README's adoption sentence says when it blocks
#           (review round 1, R-5); nor does the Builder's Guide, which ships to
#           every project as docs/reference/builders-guide.md (final check).
#       P9  every place that gives the Superpowers install also gives the
#           marketplace command for a machine that lacks it (review round 1, R-8).
#   M*  mutation proofs, one per code guard, each killed by a named case, in a
#       mirror of the tree (the mirror-and-mutate pattern of
#       tests/test-bl318-g1-test-command.sh).
#
# HERMETIC. Adoptions run with a temp HOME and CLAUDE_CONFIG_DIR and with STUB
# `claude`, `curl`, `docker`, `uvx` and `npx` first on PATH, so no case reads
# the host's Claude Code configuration or registers anything. The `claude`
# stub writes an `mcp add` where Claude Code does ($CLAUDE_CONFIG_DIR/.claude.json)
# and answers `mcp get` as Claude Code 2.1.283 prints it (tests/test-bl311-adopt-mcp.sh
# measured both). Nothing is pushed or fetched.
set -uo pipefail
export SOIF_ADOPT_MCP=off
_stock_tpl="$(git --exec-path 2>/dev/null)/../../share/git-core/templates"
if [ -d "$_stock_tpl/hooks" ]; then export GIT_TEMPLATE_DIR="$_stock_tpl"; fi
unset GITHUB_BASE_REF 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-318 G4 and G6 — the deploy detector, the refusal's claim, the stamp's words, the docs =="
for t in git jq awk; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
newtmp() { mktemp -d "$WORK/tXXXXXX"; }

CASE_DETAIL=""
check() {
  local label="$1" fn="$2"; shift 2
  CASE_DETAIL=""
  if "$fn" "$@"; then pass "$label"; else fail_ "$label" "$CASE_DETAIL"; fi
}

KPDF_BUNDLE="${BL318_KPDF_BUNDLE:-$HOME/dogfood-2026-10/k-pdf-dogfood-2.bundle}"
KPDF_AT="0bb0465"
CDF="${CDF_HOME:-$HOME/.claude-dev-framework}"
SP_CMD='claude plugin install --scope user superpowers@claude-plugins-official'

# ════════════════════════════════════════════════════════════════════════════
# D — G6(a), the deploy detectors
# ════════════════════════════════════════════════════════════════════════════
# adopt_rules FW FILE — adoption's findings for FILE, "rule<TAB>line" per line.
adopt_rules() { ( . "$1/scripts/lib/adopt/adopt-ci.sh" && _adopt_ci_rules "$2" ) 2>/dev/null; }
# scout_findings FW ROOT REL — Scout's findings for REL in a real scan of ROOT.
scout_scan() { bash "$1/scripts/scout.sh" --root "$2" </dev/null 2>/dev/null; }
scout_findings() { printf '%s' "$1" | jq -r --arg p "$2" '[.collisions.entries[]? | select(.path==$p) | .findings[]?] | sort | join(",")' 2>/dev/null; }

CI_HDR='name: ci
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:'
# The k-pdf shape (its ci.yml at 0bb0465, lines 133-149): a bash array of Nuitka
# flags, one per line, with a comment line inside the block.
KPDF_SHAPE="$CI_HDR
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Nuitka build (standalone)
        shell: bash
        run: |
          NUITKA_ARGS=(
            --standalone
            # Exclude pymupdf from compilation.
            --nofollow-import-to=pymupdf
            --no-deployment-flag=excluded-module-usage
          )
          uv run python -m nuitka \"\${NUITKA_ARGS[@]}\" k_pdf/main.py
      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: build/"

mk_git() {   # mk_git DIR — a git repo with an identity and a TypeScript file
  mkdir -p "$1/src" || return 1
  ( cd "$1" && git init -q . && git config user.email bl318g46@test.invalid && git config user.name "BL-318 G4G6" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$1/package.json"
  printf 'export const x = 1;\n' > "$1/src/index.ts"
}
commit_all() { ( cd "$1" && git add -- package.json src .github && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1; }
wf() {   # wf DIR NAME BODY — one workflow file under the push-to-main header
  mkdir -p "$1/.github/workflows" && printf '%s\n%s\n' "$CI_HDR" "$3" > "$1/.github/workflows/$2"
}

# The seven true positives (D3) and the three extra flag spellings (D2).
mk_detector_project() {   # DIR
  local d="$1"
  mk_git "$d" || return 1
  mkdir -p "$d/.github/workflows"
  printf '%s\n' "$KPDF_SHAPE" > "$d/.github/workflows/kpdf-shape.yml"
  wf "$d" flags.yml '  build:
    runs-on: ubuntu-latest
    steps:
      - run: mvn -B -Ddeploy.skip=true verify
      - run: ./build.sh "--no-deploy"
      - run: make dist FLAGS=--deploy-target=none'
  wf "$d" tp-job.yml '  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: make'
  wf "$d" tp-script.yml '  ship:
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh production'
  wf "$d" tp-pages.yml '  ship:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/deploy-pages@v4'
  wf "$d" tp-ghpages.yml '  ship:
    runs-on: ubuntu-latest
    steps:
      - uses: JamesIves/github-pages-deploy-action@v4'
  wf "$d" tp-firebase.yml '  ship:
    runs-on: ubuntu-latest
    steps:
      - run: firebase deploy --only hosting'
  wf "$d" tp-named.yml '  ship:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        run: ./ship.sh'
  wf "$d" tp-mixed.yml '  ship:
    runs-on: ubuntu-latest
    steps:
      - run: npx wrangler deploy --no-deployment-flag=x'
  # D4: an earlier flag line, then the deploy step.
  wf "$d" lineno.yml '  build:
    runs-on: ubuntu-latest
    steps:
      - run: |
          nuitka --no-deployment-flag=excluded-module-usage main.py
      - run: ./deploy.sh'
  commit_all "$d"
}
DP="$WORK/detectors"; mk_detector_project "$DP" || { echo "FATAL: detector fixture"; exit 1; }
TP_FILES="tp-job.yml tp-script.yml tp-pages.yml tp-ghpages.yml tp-firebase.yml tp-named.yml tp-mixed.yml"
# Review round 1: R-1's four (a flag before the word, on the same line), R-2's
# three (a flag's `=value`, and a command glued to a flag), and a flag named
# `deploy` itself.
TP_R1_LINES="$(cat <<'L'
tp-netlify.yml|npx -y netlify-cli deploy --prod
tp-kubectl.yml|kubectl apply -f k8s/deployment.yaml
tp-chain.yml|make --quiet;./deploy.sh
tp-rsync.yml|rsync -az --delete dist/ deploy@host:/srv/app/
tp-ansible.yml|ansible-playbook -i inventory/prod site.yml --tags=deploy
tp-nx.yml|npx nx affected --target=deploy --parallel=1
tp-glued.yml|npm ci --silent&&./deploy.sh production
tp-flagname.yml|./scripts/ci.sh --deploy
L
)"
while IFS='|' read -r _f _l; do
  [ -n "$_f" ] || continue
  wf "$DP" "$_f" "  ship:
    runs-on: ubuntu-latest
    steps:
      - run: $_l"
  TP_FILES="$TP_FILES $_f"
done <<EOF
$TP_R1_LINES
EOF
( cd "$DP" && git add -- .github && git commit -q --no-verify -m "chore: more workflows" ) >/dev/null 2>&1

case_D1() {   # FW — k-pdf's real ci.yml
  local fw="$1" k="" f="" a="" s="" scan="" bad=""
  k="$WORK/kpdf"
  if [ ! -d "$k/.git" ]; then
    git clone -q "$KPDF_BUNDLE" "$k" >/dev/null 2>&1 || { CASE_DETAIL="the bundle did not clone"; return 1; }
    ( cd "$k" && git checkout -q --detach "$KPDF_AT" ) >/dev/null 2>&1 || { CASE_DETAIL="no commit $KPDF_AT in the bundle"; return 1; }
  fi
  f="$k/.github/workflows/ci.yml"
  command grep -q -- '--no-deployment-flag' "$f" || { CASE_DETAIL="fixture: the flag is not in k-pdf's ci.yml"; return 1; }
  a="$(adopt_rules "$fw" "$f")"
  printf '%s\n' "$a" | command grep -q '^deploy-on-push' && bad="$bad [adoption: deploy-on-push at line $(printf '%s\n' "$a" | command grep '^deploy-on-push' | cut -f2)]"
  scan="$(scout_scan "$fw" "$k")"
  [ -n "$scan" ] || { CASE_DETAIL="Scout printed nothing"; return 1; }
  s="$(scout_findings "$scan" ".github/workflows/ci.yml")"
  case ",$s," in *",deploy-around-the-release-lane,"*) bad="$bad [Scout: deploy-around-the-release-lane]" ;; esac
  [ "$(printf '%s' "$scan" | jq -r '[.collisions.entries[]? | select(.path==".github/workflows/ci.yml")] | length')" = "1" ] \
    || bad="$bad [Scout did not read ci.yml at all]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_D2() {   # FW — the flag spellings: neither detector fires
  local fw="$1" scan="" f="" a="" s="" bad=""
  scan="$(scout_scan "$fw" "$DP")"
  [ -n "$scan" ] || { CASE_DETAIL="Scout printed nothing"; return 1; }
  for f in kpdf-shape.yml flags.yml; do
    a="$(adopt_rules "$fw" "$DP/.github/workflows/$f")"
    printf '%s\n' "$a" | command grep -q '^deploy-on-push' && bad="$bad [adoption fires on $f]"
    s="$(scout_findings "$scan" ".github/workflows/$f")"
    case ",$s," in *",deploy-around-the-release-lane,"*) bad="$bad [Scout fires on $f]" ;; esac
  done
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_D3() {   # FW — every real deploy step still fires, in both detectors
  local fw="$1" scan="" f="" a="" s="" bad=""
  scan="$(scout_scan "$fw" "$DP")"
  [ -n "$scan" ] || { CASE_DETAIL="Scout printed nothing"; return 1; }
  for f in $TP_FILES; do
    a="$(adopt_rules "$fw" "$DP/.github/workflows/$f")"
    printf '%s\n' "$a" | command grep -q '^deploy-on-push' || bad="$bad [adoption misses $f]"
    s="$(scout_findings "$scan" ".github/workflows/$f")"
    case ",$s," in *",deploy-around-the-release-lane,"*) : ;; *) bad="$bad [Scout misses $f]" ;; esac
  done
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_D4() {   # FW — adoption names the deploy step's line
  local fw="$1" f="$DP/.github/workflows/lineno.yml" want="" got=""
  want="$(command grep -n 'deploy.sh' "$f" | cut -d: -f1)"
  got="$(adopt_rules "$fw" "$f" | command grep '^deploy-on-push' | cut -f2)"
  CASE_DETAIL="reported line '$got', the deploy step is line $want"
  [ -n "$want" ] && [ "$got" = "$want" ]
}

# The flag rules, read off their marker lines: the strip pattern (inside gsub) and
# the whole-name pattern (the one a `~` tests) of each detector.
flag_re()  { command grep -F -- "$2" "$1" | sed -n 's/.*gsub(\/\(.*\)\/, " ", [a-z]*).*/\1/p' | head -1; }
whole_re() { command grep -F -- "$2" "$1" | sed -n 's/.* ~ \/\(.*\)\/ { [a-z]* = [a-z]* " deploy" }.*/\1/p' | head -1; }
case_D5() {   # FW — one rule, two copies
  local fw="$1" a="" s="" aw="" sw="" bad=""
  a="$(flag_re "$fw/scripts/lib/adopt/adopt-ci.sh" '# BL-318-G6-DEPLOY-FLAG')"
  s="$(flag_re "$fw/scripts/lib/scout/scout-collisions.sh" '# BL-318-G6-DEPLOY-FLAG-SCOUT')"
  aw="$(whole_re "$fw/scripts/lib/adopt/adopt-ci.sh" '# BL-318-G6-DEPLOY-WHOLE')"
  sw="$(whole_re "$fw/scripts/lib/scout/scout-collisions.sh" '# BL-318-G6-DEPLOY-WHOLE-SCOUT')"
  [ -n "$a" ] && [ -n "$s" ] || bad="$bad [a strip pattern could not be read: adopt='$a' scout='$s']"
  [ -n "$aw" ] && [ -n "$sw" ] || bad="$bad [a whole-name pattern could not be read: adopt='$aw' scout='$sw']"
  [ "$a" = "$s" ] || bad="$bad [the strip patterns differ: adopt='$a' scout='$s']"
  [ "$aw" = "$sw" ] || bad="$bad [the whole-name patterns differ: adopt='$aw' scout='$sw']"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

echo
echo "=== D — G6(a): a word inside a command-line flag is not a deploy ==="
if [ -f "$KPDF_BUNDLE" ]; then
  check "D1 k-pdf's real ci.yml (bundle, $KPDF_AT): no deploy finding from adoption or from a real Scout" case_D1 "$REPO_ROOT"
else
  skip "D1 k-pdf's real ci.yml" "no bundle at $KPDF_BUNDLE (CI has none; D2 carries the same shape)"
fi
check "D2 Nuitka's --no-deployment-flag and three more flag spellings: neither detector fires" case_D2 "$REPO_ROOT"
check "D3 fifteen real deploy steps (a job, a script, two Pages actions, firebase, a step name, one beside a flag, and review round 1's eight): both detectors fire on each" case_D3 "$REPO_ROOT"
check "D4 adoption reports the deploy step's line, not the earlier flag's" case_D4 "$REPO_ROOT"
check "D5 the two detectors' flag rules are byte-identical (strip and whole-name patterns)" case_D5 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# B — G6(b), what the refusal says about writes outside the project
# ════════════════════════════════════════════════════════════════════════════
mkstubs() {   # DIR
  local d="$1"
  mkdir -p "$d" || return 1
  cat > "$d/claude" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
{ printf 'claude'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$st/calls.log"
if [ ! -t 0 ]; then cat >/dev/null; fi
[ -f "$st/claude-fails" ] && { echo "stub claude: refusing on purpose" >&2; exit 1; }
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then f="$CLAUDE_CONFIG_DIR/.claude.json"; else f="$HOME/.claude.json"; fi
if [ "${1:-}" = mcp ] && [ "${2:-}" = get ]; then
  jq -e --arg n "${3:-}" '.mcpServers[$n]' "$f" >/dev/null 2>&1 || { echo "No MCP server found with name: ${3:-}" >&2; exit 1; }
  printf '%s:\n  Scope: User config (available in all your projects)\n  Status: \342\234\224 Connected\n\nTo remove this server, run: claude mcp remove %s -s user\n' "$3" "$3"
  exit 0
fi
[ "${1:-}" = mcp ] && [ "${2:-}" = add ] || exit 0
shift 2
name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    -s|--scope) shift 2 ;;
    -e) shift; while [ $# -gt 0 ]; do case "$1" in -*) break ;; *) shift ;; esac; done ;;
    -*) shift ;;
    *) [ -z "$name" ] && name="$1"; shift ;;
  esac
done
[ -n "$name" ] && [ $# -gt 0 ] || { echo "stub claude: missing name or command" >&2; exit 1; }
mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{}' > "$f"
jq --arg n "$name" --arg c "$1" '.mcpServers[$n] = {type: "stdio", command: $c}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
echo "Added stdio MCP server $name"
STUB
  cat > "$d/curl" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
u=""; for a in "$@"; do u="$a"; done
if [ ! -t 0 ]; then cat >/dev/null; fi
case "$u" in *localhost:6333*|*127.0.0.1:6333*) [ -f "$st/qdrant-up" ] && exit 0 ;; esac
exit 7
STUB
  cat > "$d/docker" <<'STUB'
#!/bin/bash
st="${STUB_STATE:?}"
if [ ! -t 0 ]; then cat >/dev/null; fi
case "${1:-}" in info) [ -f "$st/docker-up" ] ;; *) exit 0 ;; esac
STUB
  printf '#!/bin/bash\nexit 0\n' > "$d/uvx"
  printf '#!/bin/bash\nexit 0\n' > "$d/npx"
  chmod +x "$d"/*
}
STUBS="$WORK/stubs"; mkstubs "$STUBS" || { echo "FATAL: stubs"; exit 1; }

b_case() {   # b_case TAG — a fresh HOME, CLAUDE_CONFIG_DIR, stub state and adoptee
  C="$(mktemp -d "$WORK/$1.XXXXXX")" || return 1
  H="$C/home"; CFG="$C/cfg"; ST="$C/state"; P="$C/proj"
  mkdir -p "$H" "$CFG" "$ST" "$C/w" || return 1
  : > "$ST/calls.log"
  : > "$ST/qdrant-up"          # a database already answers at localhost:6333
  mk_git "$P" || return 1
  mkdir -p "$P/.github/workflows" && printf '%s\n' "$KPDF_SHAPE" > "$P/.github/workflows/ci.yml"
  commit_all "$P"
}
b_register() {   # b_register NAME — registered before the run
  [ -f "$CFG/.claude.json" ] || echo '{}' > "$CFG/.claude.json"
  jq --arg n "$1" '.mcpServers[$n] = {command: "npx"}' "$CFG/.claude.json" > "$CFG/.claude.json.tmp" && mv "$CFG/.claude.json.tmp" "$CFG/.claude.json"
}
# The MCP step alone, then a refusal, in one shell — the way the driver runs them.
cat > "$WORK/harness.sh" <<'HARN'
set -uo pipefail
ADOPT_FRAMEWORK_ROOT="$1"; ADOPT_CORE_LIB_DIR="$1/scripts/lib"; ADOPT_WORK="$2"
. "$ADOPT_CORE_LIB_DIR/helpers-core.sh"
. "$1/scripts/lib/adopt/adopt-core.sh"
. "$1/scripts/lib/adopt/adopt-mcp.sh"
adopt_stdin_init
adopt_mcp_resolve "$3" > "$2/step.out" 2>&1
[ "${4:-}" = touched ] && adopt_touched_disk
if [ "${4:-}" = block ]; then ADOPT_OPERATION="Adoption" adopt_block "harness cause"; else ADOPT_OPERATION="Adoption" adopt_refuse "harness cause"; fi
HARN
b_step() {   # b_step FW ANSWER [touched|block] — the refusal text in $C/out
  ( cd "$P" && printf '%s\n' "$2" | env PATH="$STUBS:$PATH" HOME="$H" CLAUDE_CONFIG_DIR="$CFG" STUB_STATE="$ST" \
      SOIF_ADOPT_MCP= SOIF_ADOPT_QDRANT_WAIT=2 bash "$WORK/harness.sh" "$1" "$C/w" "$P" "${3:-}" ) > "$C/out" 2>&1
}
# the two lines a registration must produce, per name
says_registered() {   # FILE NAME
  command grep -q "register.*$2" "$1" && command grep -qF "claude mcp remove -s user $2" "$1"
}
NOTHING_TO_PROJECT='Nothing was committed and nothing was written to this project.'
OLD_SENTENCE='Nothing was committed and nothing was written.'

case_B1() {   # FW — the dogfood shape, end to end
  local fw="$1" bad="" head0="" o=""
  command -v gitleaks >/dev/null 2>&1 || { CASE_DETAIL="gitleaks is not on PATH (a personal adoption stops for it first)"; return 1; }
  b_case b1 || { CASE_DETAIL="fixture"; return 1; }
  head0="$(git -C "$P" rev-parse HEAD)"
  ( cd "$P" && printf '1\nstandard\nset it up now\n' | env PATH="$STUBS:$PATH" HOME="$H" CLAUDE_CONFIG_DIR="$CFG" STUB_STATE="$ST" \
      SOIF_ADOPT_MCP= SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" SOIF_ADOPT_QDRANT_WAIT=2 \
      bash "$fw/scripts/adopt-project.sh" ) > "$C/out" 2>&1
  local rc=$?
  o="$C/out"
  [ "$rc" -eq 1 ] || bad="$bad [rc $rc, want 1]"
  command grep -q 'BLOCKED\] This question has no default' "$o" || bad="$bad [not stopped, as a block, at a mandatory question: $(command grep -E 'REFUSED|BLOCKED' "$o" | head -1)]"
  jq -e '.mcpServers.context7 and .mcpServers.qdrant' "$CFG/.claude.json" >/dev/null 2>&1 || bad="$bad [fixture: the run did not register both]"
  command grep -qF "$NOTHING_TO_PROJECT" "$o" || bad="$bad [no 'nothing was written to this project']"
  command grep -qxF "          Adoption did not begin. $OLD_SENTENCE" "$o" && bad="$bad [the old sentence is still printed]"
  command grep -q 'did not begin' "$o" && bad="$bad [a run that registered two servers says adoption did not begin]"
  says_registered "$o" context7 || bad="$bad [context7's registration not named, with its remove command]"
  says_registered "$o" qdrant || bad="$bad [qdrant's registration not named, with its remove command]"
  command grep -qF 'claude mcp list' "$o" || bad="$bad [no claude mcp list]"
  [ "$(git -C "$P" rev-parse HEAD)" = "$head0" ] || bad="$bad [HEAD moved]"
  [ -z "$(git -C "$P" status --porcelain)" ] || bad="$bad [the project changed: $(git -C "$P" status --porcelain | head -2 | tr '\n' ' ')]"
  # G6(a) end to end: the k-pdf-shaped ci.yml is read and found clean.
  command grep -q 'none matched a known way around' "$o" || bad="$bad [the CI section did not read ci.yml as clean]"
  command grep -q 'deploys on a branch push' "$o" && bad="$bad [the CI section still reports a deploy]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_B2() {   # FW — skip: nothing outside is named
  local fw="$1" bad=""
  b_case b2 || { CASE_DETAIL="fixture"; return 1; }
  b_step "$fw" "skip it"
  command grep -q '^\[REFUSED\] harness cause' "$C/out" || bad="$bad [nothing ran, so it is a refusal, not a block]"
  command grep -qxF "          Adoption did not begin. $NOTHING_TO_PROJECT" "$C/out" || bad="$bad [no 'did not begin. $NOTHING_TO_PROJECT']"
  command grep -q 'claude mcp remove' "$C/out" && bad="$bad [names a registration that never happened]"
  command grep -q '\[mcp\] \[add\]' "$ST/calls.log" && bad="$bad [fixture: something was registered]"
  CASE_DETAIL="${bad:-} out: $(tr '\n' '|' < "$C/out" | cut -c1-300)"
  [ -z "$bad" ]
}

case_B3() {   # FW — the commands fail: nothing is claimed
  local fw="$1" bad=""
  b_case b3 || { CASE_DETAIL="fixture"; return 1; }
  : > "$ST/claude-fails"
  b_step "$fw" "set it up now"
  command grep -q '\[mcp\] \[add\]' "$ST/calls.log" || bad="$bad [fixture: no add was attempted]"
  command grep -q '^\[REFUSED\] harness cause' "$C/out" || bad="$bad [nothing was registered, so it is a refusal, not a block]"
  command grep -qF "$NOTHING_TO_PROJECT" "$C/out" || bad="$bad [no 'nothing was written to this project']"
  command grep -q 'claude mcp remove' "$C/out" && bad="$bad [claims a registration the receipt does not show]"
  CASE_DETAIL="${bad:-} out: $(tr '\n' '|' < "$C/out" | cut -c1-300)"
  [ -z "$bad" ]
}

case_B4() {   # FW — registered before the run: not this run's
  local fw="$1" bad=""
  b_case b4 || { CASE_DETAIL="fixture"; return 1; }
  b_register context7
  b_step "$fw" "set it up now"
  says_registered "$C/out" qdrant || bad="$bad [qdrant, which this run registered, is not named]"
  command grep -q '^\[BLOCKED\] harness cause' "$C/out" || bad="$bad [a stop after a registration is not labelled a block]"
  command grep -qxF "          Adoption stopped before it changed this project. $NOTHING_TO_PROJECT" "$C/out" || bad="$bad [no 'stopped before it changed this project']"
  command grep -q 'ATTEMPTED' "$C/out" && bad="$bad [says it attempted writes to the project]"
  command grep -q 'claude mcp remove -s user context7' "$C/out" && bad="$bad [context7 was registered before the run, and is named as this run's]"
  CASE_DETAIL="${bad:-} out: $(tr '\n' '|' < "$C/out" | cut -c1-300)"
  [ -z "$bad" ]
}

case_B5() {   # FW — a BLOCKED refusal names it too
  local fw="$1" bad=""
  b_case b5 || { CASE_DETAIL="fixture"; return 1; }
  b_step "$fw" "set it up now" touched
  command grep -q 'BLOCKED\] harness cause' "$C/out" || bad="$bad [fixture: not the BLOCKED arm]"
  says_registered "$C/out" context7 || bad="$bad [context7 not named in a BLOCKED refusal]"
  says_registered "$C/out" qdrant || bad="$bad [qdrant not named in a BLOCKED refusal]"
  CASE_DETAIL="${bad:-} out: $(tr '\n' '|' < "$C/out" | cut -c1-300)"
  [ -z "$bad" ]
}

case_B6() {   # FW — the forced-block arm after a registration (review round 1, R-4)
  local fw="$1" bad=""
  b_case b6 || { CASE_DETAIL="fixture"; return 1; }
  b_step "$fw" "set it up now" block
  command grep -q '^\[BLOCKED\] harness cause' "$C/out" || bad="$bad [fixture: not a block]"
  command grep -qxF "          Adoption stopped before it changed this project. $NOTHING_TO_PROJECT" "$C/out" || bad="$bad [no 'stopped before it changed this project']"
  says_registered "$C/out" context7 || bad="$bad [context7 not named after adopt_block]"
  says_registered "$C/out" qdrant || bad="$bad [qdrant not named after adopt_block]"
  CASE_DETAIL="${bad:-} out: $(tr '\n' '|' < "$C/out" | cut -c1-300)"
  [ -z "$bad" ]
}

echo
echo "=== B — G6(b): the refusal is true about writes outside the project ==="
check "B1 the dogfood shape (whole adoption): servers registered, then refused — 'nothing was written to this project', both named, with claude mcp list / remove; the project untouched; its ci.yml read as clean" case_B1 "$REPO_ROOT"
check "B2 skip: the refusal names nothing outside the project" case_B2 "$REPO_ROOT"
check "B3 the claude commands fail: nothing is claimed" case_B3 "$REPO_ROOT"
check "B4 Context7 registered before the run: only Qdrant is named" case_B4 "$REPO_ROOT"
check "B5 a BLOCKED refusal names the registration too" case_B5 "$REPO_ROOT"
check "B6 a forced block after a registration names it too" case_B6 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# C — G6(c), the stamp's words
# ════════════════════════════════════════════════════════════════════════════
case_C1() {   # FW — no "was adopted at" where a user reads it
  local fw="$1" hits=""
  hits="$(cd "$fw" && command grep -rn -i 'was adopted at\|the adoption commit, and the stamp' scripts/ templates/ docs/adoption.md docs/user-guide.md README.md 2>/dev/null)"
  CASE_DETAIL="$(printf '%s' "$hits" | head -3 | tr '\n' '|')"
  [ -z "$hits" ]
}

cat > "$WORK/act4.sh" <<'A4'
set -uo pipefail
ADOPT_DC_TAXONOMY="public internal confidential pii financial health regulated"
. "$1/scripts/lib/adopt/adopt-act4.sh"
_adopt_act4_record_errors "$2"
A4
case_C2() {   # FW — the finisher's refusal, run
  local fw="$1" r="" out=""
  r="$(newtmp)"; mkdir -p "$r/.claude/adoption"
  printf '{"adoption":{"adopted":true,"adoptedAtCommit":"1111111111111111111111111111111111111111"}}\n' > "$r/.claude/manifest.json"
  printf '{"schemaVersion":1,"adoptedAtCommit":"2222222222222222222222222222222222222222"}\n' > "$r/.claude/adoption/assessment-record.json"
  out="$(bash "$WORK/act4.sh" "$fw" "$r" 2>&1 | command grep adoptedAtCommit)"
  CASE_DETAIL="the refusal line: '$out'"
  printf '%s' "$out" | command grep -qF 'adoptedAtCommit is not the commit adoption started from (1111111111111111111111111111111111111111' \
    && ! printf '%s' "$out" | command grep -q 'was adopted at'
}

echo
echo "=== C — G6(c): adoptedAtCommit is the commit adoption started from ==="
check "C1 no shipped script and no user doc says 'was adopted at'" case_C1 "$REPO_ROOT"
check "C2 the finisher refuses a record naming another commit in the new words" case_C2 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# P — G4, doc claims a script can check
# ════════════════════════════════════════════════════════════════════════════
# section FILE START-REGEX — from the first line matching START up to the next
# heading of the same or a higher level.
section() {
  awk -v re="$2" '
    !on && $0 ~ re { on = 1; match($0, /^#+/); lvl = RLENGTH; print; next }
    on && /^#+ / { match($0, /^#+/); if (RLENGTH <= lvl) exit }
    on { print }' "$1"
}

case_P1() {   # FW
  local fw="$1" s="" m="" bad=""
  s="$(section "$fw/docs/adoption.md" '^### What you need$')"
  [ -n "$s" ] || { CASE_DETAIL="no '### What you need' section"; return 1; }
  printf '%s' "$s" | command grep -q 'Superpowers' || bad="$bad [Superpowers is not named]"
  printf '%s' "$s" | command grep -qF "$SP_CMD" || bad="$bad [the install command is not there verbatim]"
  printf '%s' "$s" | command grep -qF 'BLOCKED — Source file edit requires the Superpowers workflow' || bad="$bad [the block a session prints is not quoted]"
  m="$(jq -r '.tools[] | select(.name == "Superpowers") | .install.darwin_brew' "$fw/templates/tool-matrix/common.json")"
  [ "$m" = "$SP_CMD" ] || bad="$bad [the tool matrix installs '$m', not the documented command]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_P2() {   # FW
  local fw="$1" a="" pre="" bad="" t=""
  a="$(section "$fw/README.md" '^### Adoption — the second way in$')"
  pre="$(section "$fw/README.md" '^## Prerequisites$')"
  [ -n "$a" ] && [ -n "$pre" ] || { CASE_DETAIL="a README section is missing"; return 1; }
  printf '%s' "$a" | command grep -qF 'docs/adoption.md#what-you-need' || bad="$bad [the adoption section does not link to What you need]"
  printf '%s' "$pre" | command grep -qF 'docs/adoption.md#what-you-need' || bad="$bad [Prerequisites does not link to What you need]"
  for t in jq gitleaks semgrep shasum; do
    printf '%s' "$a" | command grep -qF "\`$t\`" && bad="$bad [the adoption section names \`$t\` itself — a second list]"
  done
  command grep -qx '### What you need' "$fw/docs/adoption.md" || bad="$bad [the link's target heading is gone]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_P3() {   # FW
  local fw="$1" pre="" opt="" bad=""
  pre="$(section "$fw/README.md" '^## Prerequisites$')"
  printf '%s' "$pre" | command grep -F '| **Superpowers** |' | command grep -qF "\`$SP_CMD\`" || bad="$bad [no Superpowers row with its command under Prerequisites]"
  opt="$(awk '/^\*\*Optional enhancements/{on=1} on && /^See the \[CLI Setup Addendum\]/{exit} on' "$fw/README.md")"
  [ -n "$opt" ] || bad="$bad [fixture: no Optional enhancements table]"
  printf '%s' "$opt" | command grep -q 'Superpowers' && bad="$bad [Superpowers is still listed as optional]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

# Each Guardrails message the docs quote, with the hook that prints it. "@REV"
# reads that hook at a commit of the clone instead of its working tree.
QUOTES="$(cat <<'Q'
docs/adoption.md|hooks/enforce-superpowers.sh|BLOCKED — Source file edit requires the Superpowers workflow, but the Superpowers plugin is not enabled in this Claude Code configuration
docs/adoption.md|hooks/enforce-superpowers.sh@ea2025a|You MUST invoke superpowers:brainstorming before editing source files
docs/adoption.md|hooks/stop-checklist.sh|Uncommitted source changes. Commit before finishing.
docs/adoption.md|hooks/enforce-evaluate.sh|BLOCKED — Commit requires
docs/adoption.md|hooks/record-approval.sh|The pending question cannot be answered
docs/adoption.md|hooks/record-approval.sh|Reply with the option id again
docs/adoption.md|hooks/mark-evaluated.sh|in a separate terminal
Q
)"
case_P4() {   # FW
  local fw="$1" doc="" hook="" text="" rev="" body="" bad=""
  while IFS='|' read -r doc hook text; do
    [ -n "$doc" ] || continue
    command grep -qF -- "$text" "$fw/$doc" || bad="$bad [$doc does not quote: $text]"
    rev=""; case "$hook" in *@*) rev="${hook#*@}"; hook="${hook%@*}" ;; esac
    if [ -n "$rev" ]; then body="$(git -C "$CDF" show "$rev:$hook" 2>/dev/null)"; else body="$(cat "$CDF/$hook" 2>/dev/null)"; fi
    [ -n "$body" ] || { bad="$bad [the clone has no $hook${rev:+ at $rev}]"; continue; }
    printf '%s' "$body" | command grep -qF -- "$text" || bad="$bad [$hook${rev:+@$rev} does not print: $text]"
  done <<EOF
$QUOTES
EOF
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_P5() {   # FW — each kind of session-start message: named in the guide, printed by a script
  local fw="$1" g="" k="" src="" bad=""
  g="$(section "$fw/docs/user-guide.md" '^#### What to do with each message$')"
  [ -n "$g" ] || { CASE_DETAIL="no '#### What to do with each message' in docs/user-guide.md"; return 1; }
  while IFS='|' read -r k src; do
    [ -n "$k" ] || continue
    printf '%s' "$g" | command grep -qF -- "$k" || bad="$bad [the guide does not name: $k]"
    command grep -qF -- "$k" "$fw/$src" || bad="$bad [$src does not print: $k]"
  done <<'EOF'
Update commands (run manually):|scripts/check-versions.sh
URGENT — VERSION CHECK FAILED|scripts/session-version-check.sh
BELOW MINIMUM|scripts/check-versions.sh
GUARDRAILS UPDATE OFFER|scripts/session-version-check.sh
GUARDRAILS NOTICE|scripts/session-version-check.sh
cannot tell whether an update is available|scripts/check-versions.sh
a new MAJOR version|scripts/check-versions.sh
NOT registered with Claude Code|scripts/check-versions.sh
EOF
  section "$fw/docs/adoption.md" '^### 6\. Afterwards$' | command grep -qF 'user-guide.md#what-to-do-with-each-message' \
    || bad="$bad [adoption.md section 6 does not link to it]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_P6() {   # FW — the phase-0 paragraph's citation is true
  local fw="$1" body="" bad=""
  section "$fw/docs/adoption.md" '^### 7\. Your first change$' | command grep -qF '`check_commit_ready`' \
    || bad="$bad [section 7 does not cite check_commit_ready]"
  body="$(awk '/^check_commit_ready\(\) \{/{on=1} on{print} on && /^\}/{exit}' "$fw/scripts/process-checklist.sh")"
  printf '%s' "$body" | command grep -qF '"$current_phase" -lt 2 ]' || bad="$bad [check_commit_ready no longer lets everything through below phase 2]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_P7() {   # FW — the override clears the recorded question first
  local fw="$1" o="" bad=""
  o="$(awk '/^\*\*The override\.\*\*/{on=1} on && /^\*\*The commit.s own checks\.\*\*/{exit} on' "$fw/docs/adoption.md")"
  [ -n "$o" ] || { CASE_DETAIL="no 'The override.' paragraph in section 7"; return 1; }
  printf '%s' "$o" | command grep -qF 'bash scripts/pending-approval.sh --resolve' || bad="$bad [the override does not clear the recorded question]"
  command grep -qE '^[[:space:]]+--resolve' "$fw/scripts/pending-approval.sh" || bad="$bad [pending-approval.sh has no --resolve]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

case_P8() {   # FW — Superpowers is nowhere optional
  local fw="$1" bad="" hits=""
  hits="$(command grep -n -i 'superpowers' "$fw/docs/user-guide.md" | command grep -i 'optional')"
  [ -z "$hits" ] || bad="$bad [user-guide.md calls it optional: $(printf '%s' "$hits" | head -2 | tr '\n' '|')]"
  hits="$(command grep -n -i 'superpowers' "$fw/docs/builders-guide.md" | command grep -i -E 'optional|recommended')"
  [ -z "$hits" ] || bad="$bad [builders-guide.md calls it optional or recommended: $(printf '%s' "$hits" | head -2 | tr '\n' '|')]"
  command grep -A3 'Superpowers plugin not found' "$fw/init.sh" | command grep -qi 'recommended' && bad="$bad [init.sh still calls it recommended]"
  command grep -q 'Superpowers plugin not found' "$fw/init.sh" || bad="$bad [fixture: init.sh's message is gone]"
  section "$fw/README.md" '^### Adoption — the second way in$' | tr '\n' ' ' | command grep -q 'when the Development Guardrails are installed' \
    || bad="$bad [README's adoption sentence says it blocks without saying when]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

MKT_CMD='claude plugin marketplace add anthropics/claude-plugins-official'
case_P9() {   # FW — the marketplace line goes with every install
  local fw="$1" f="" n_sp="" n_mk="" bad=""
  for f in README.md docs/adoption.md docs/user-guide.md; do
    n_sp="$(command grep -cF "$SP_CMD" "$fw/$f")"
    n_mk="$(command grep -cF "$MKT_CMD" "$fw/$f")"
    [ "$n_sp" -ge 1 ] || bad="$bad [$f gives no install]"
    [ "$n_mk" -ge 1 ] || bad="$bad [$f gives the install but not the marketplace command]"
  done
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

echo
echo "=== P — G4: what the docs claim, checked ==="
check "P1 adoption.md 'What you need' names Superpowers, its exact command (the tool matrix's) and the block without it" case_P1 "$REPO_ROOT"
check "P2 one prerequisites list: README links to adoption.md#what-you-need from both places and lists no adoption tool itself" case_P2 "$REPO_ROOT"
check "P3 README lists Superpowers under Prerequisites, not as an optional enhancement" case_P3 "$REPO_ROOT"
if [ -d "$CDF/hooks" ] && [ -d "$CDF/.git" ]; then
  check "P4 every Guardrails message the docs quote is printed by the Guardrails hooks ($CDF)" case_P4 "$REPO_ROOT"
else
  skip "P4 the quoted Guardrails messages" "no Guardrails clone at $CDF"
fi
check "P5 the session-start guidance names each kind of message, and each is real script output" case_P5 "$REPO_ROOT"
check "P6 the phase-0 paragraph cites check_commit_ready, which lets every commit through below phase 2" case_P6 "$REPO_ROOT"
check "P7 the override clears the recorded question first (bash scripts/pending-approval.sh --resolve)" case_P7 "$REPO_ROOT"
check "P8 Superpowers is not called optional or recommended anywhere it is required (user guide, Builder's Guide, init.sh, README)" case_P8 "$REPO_ROOT"
check "P9 every Superpowers install comes with the marketplace command" case_P9 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# M — every G6 code guard is load-bearing
# ════════════════════════════════════════════════════════════════════════════
echo
echo "=== M — every BL-318 G6 marker is load-bearing ==="
mk_mirror() {
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$1/README.md" "$1/docs" "$2/"
}
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
mutant() {   # mutant ID REL MARKER REPLACEMENT KILLER WHAT
  local id="$1" rel="$2" mark="$3" repl="$4" killer="$5" what="$6" m="" why=""
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  # A detector mutant is awk inside a quoted string, which `bash -n` cannot see:
  # run the mutant detector once, and an awk that does not parse (exit 2) would
  # make every case fail, so it would read as a kill. Refuse it instead.
  local arc=0
  case "$rel" in
    "$AC") ( . "$m/$AC" && _adopt_ci_rules /dev/null ) >/dev/null 2>&1 || arc=$? ;;
    "$SC") ( . "$m/$SC" && _scout_deploy_word /dev/null ) >/dev/null 2>&1 || arc=$? ;;
  esac
  [ "$arc" -ne 2 ] || { fail_ "$id" "the mutant's awk does not parse — a kill would prove nothing"; return; }
  CASE_DETAIL=""
  if "$killer" "$m"; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_}"
  fi
}
# mutant_pair ID REL1 MARK1 REPL1 REL2 MARK2 REPL2 KILLER WHAT — one mutant
# applied to TWO files in the same mirror: the two detector copies changed
# together, so D5 (which compares them) cannot be what kills it.
mutant_pair() {
  local id="$1" r1="$2" k1="$3" p1="$4" r2="$5" k2="$6" p2="$7" killer="$8" what="$9" m="" why="" arc=0
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$r1" "$k1" "$p1")" || { fail_ "$id" "mutant did not land in $r1: $why"; return; }
  why="$(mutate "$m/$r2" "$k2" "$p2")" || { fail_ "$id" "mutant did not land in $r2: $why"; return; }
  ( . "$m/$AC" && _adopt_ci_rules /dev/null ) >/dev/null 2>&1 || arc=$?
  [ "$arc" -ne 2 ] || { fail_ "$id" "the adoption mutant's awk does not parse"; return; }
  arc=0; ( . "$m/$SC" && _scout_deploy_word /dev/null ) >/dev/null 2>&1 || arc=$?
  [ "$arc" -ne 2 ] || { fail_ "$id" "the Scout mutant's awk does not parse"; return; }
  CASE_DETAIL=""
  if "$killer" "$m"; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_}"
  fi
}
AC=scripts/lib/adopt/adopt-ci.sh
SC=scripts/lib/scout/scout-collisions.sh
AM=scripts/lib/adopt/adopt-mcp.sh
ACO=scripts/lib/adopt/adopt-core.sh
A4=scripts/lib/adopt/adopt-act4.sh
# The detectors as they were: every "deploy" counts.
AC_OLD='    { word = line }'
SC_OLD='    { l = " " tolower($0); w = l }'
# Read from heredocs with `read`, not `$(cat <<…)`: bash 3.2 mis-parses a lone
# quote inside a heredoc inside a command substitution.
# Over-stripping: any dash starts a "flag", so a hyphenated action name loses its deploy.
IFS= read -r AC_OVER <<'R' || :
    { word = " " line; gsub(/-+[a-z0-9][^[:space:]"'\'',)=;&|<>]*/, " ", word) }
R
IFS= read -r SC_OVER <<'R' || :
    { l = " " tolower($0); w = l; gsub(/-+[a-z0-9][^[:space:]"'\'',)=;&|<>]*/, " ", w) }
R
# Review round 1, R-1: a flag no longer ends at whitespace, so it swallows its line.
IFS= read -r AC_NOSPACE <<'R' || :
    { word = " " line; gsub(/[[:space:]"'\''(,=]--?[a-z0-9][^"'\'',)=;&|<>]*/, " ", word) }
R
IFS= read -r SC_NOSPACE <<'R' || :
    { l = " " tolower($0); w = l; gsub(/[[:space:]"'\''(,=]--?[a-z0-9][^"'\'',)=;&|<>]*/, " ", w) }
R
# Review round 1, R-2: the first cut's end class — a flag takes its =value and a glued command.
IFS= read -r AC_R2 <<'R' || :
    { word = " " line; gsub(/[[:space:]"'\''(,=]--?[a-z0-9][^[:space:]"'\'',)]*/, " ", word) }
R
IFS= read -r SC_R2 <<'R' || :
    { l = " " tolower($0); w = l; gsub(/[[:space:]"'\''(,=]--?[a-z0-9][^[:space:]"'\'',)]*/, " ", w) }
R
# One copy's whole-name pattern drifts (`:` dropped from its class): D5 must see it.
IFS= read -r AC_WHOLE_DRIFT <<'R' || :
    (" " line) ~ /[[:space:]"'\''(,=]--?deploy([^a-z0-9_.-]|$)/ { word = word " deploy" }
R
mutant MA1 "$AC" '# BL-318-G6-DEPLOY-FLAG' "$AC_OLD" case_D2 "adoption counts the word inside a flag again (the dogfood false positive)"
mutant MA2 "$AC" '# BL-318-G6-DEPLOY-FLAG' "$AC_OLD" case_D4 "adoption reports the flag's line again"
mutant MA3 "$AC" '# BL-318-G6-DEPLOY-FLAG' "$AC_OVER" case_D3 "adoption strips from any dash and misses github-pages-deploy-action"
mutant MA5 "$AC" '# BL-318-G6-DEPLOY-FLAG' "$AC_NOSPACE" case_D3 "adoption: a flag swallows the rest of its line (review round 1, R-1)"
mutant MA6 "$AC" '# BL-318-G6-DEPLOY-FLAG' "$AC_R2" case_D3 "adoption: a flag takes its =value and a glued command (review round 1, R-2)"
mutant MA7 "$AC" '# BL-318-G6-DEPLOY-WHOLE' '    { }' case_D3 "adoption: a flag named deploy no longer counts"
mutant MA8 "$AC" '# BL-318-G6-DEPLOY-FLAG' "$AC_R2" case_D5 "adoption's strip pattern drifts from Scout's (review round 1, R-7)"
mutant MA9 "$AC" '# BL-318-G6-DEPLOY-WHOLE' "$AC_WHOLE_DRIFT" case_D5 "adoption's whole-name pattern drifts from Scout's (review round 1, R-7)"
# The final check's mB: `;` dropped from BOTH strip classes, so a flag runs on
# through a `;` and the command glued after it.
IFS= read -r AC_NOSEMI <<'R' || :
    { word = " " line; gsub(/[[:space:]"'\''(,=]--?[a-z0-9][^[:space:]"'\'',)=&|<>]*/, " ", word) }
R
IFS= read -r SC_NOSEMI <<'R' || :
    { l = " " tolower($0); w = l; gsub(/[[:space:]"'\''(,=]--?[a-z0-9][^[:space:]"'\'',)=&|<>]*/, " ", w) }
R
mutant_pair MAS1 "$AC" '# BL-318-G6-DEPLOY-FLAG' "$AC_NOSEMI" "$SC" '# BL-318-G6-DEPLOY-FLAG-SCOUT' "$SC_NOSEMI" case_D3 "both detectors: a flag runs on through ';' (the final check's mB)"
mutant MS1 "$SC" '# BL-318-G6-DEPLOY-FLAG-SCOUT' "$SC_OLD" case_D2 "Scout counts the word inside a flag again"
mutant MS2 "$SC" '# BL-318-G6-DEPLOY-FLAG-SCOUT' "$SC_OVER" case_D3 "Scout strips from any dash and misses github-pages-deploy-action"
mutant MS4 "$SC" '# BL-318-G6-DEPLOY-FLAG-SCOUT' "$SC_NOSPACE" case_D3 "Scout: a flag swallows the rest of its line (review round 1, R-1)"
mutant MS5 "$SC" '# BL-318-G6-DEPLOY-FLAG-SCOUT' "$SC_R2" case_D3 "Scout: a flag takes its =value and a glued command (review round 1, R-2)"
mutant MS6 "$SC" '# BL-318-G6-DEPLOY-WHOLE-SCOUT' '    { }' case_D3 "Scout: a flag named deploy no longer counts"
if [ -f "$KPDF_BUNDLE" ]; then
  mutant MA4 "$AC" '# BL-318-G6-DEPLOY-FLAG' "$AC_OLD" case_D1 "adoption flags k-pdf's real ci.yml again"
  mutant MS3 "$SC" '# BL-318-G6-DEPLOY-FLAG-SCOUT' "$SC_OLD" case_D1 "Scout flags k-pdf's real ci.yml again"
fi
mutant MB1 "$AM" '# BL-318-G6-MCP-ATTEMPT' '        :' case_B4 "no attempted registration is recorded, so nothing is named"
mutant MB2 "$AM" '# BL-318-G6-MCP-REG-Q' '    :' case_B4 "Qdrant's registration is never named"
mutant MB3 "$AM" '# BL-318-G6-MCP-REG-C7' '    case " $added " in *" context7 "*) ADOPT_MCP_REGISTERED="${ADOPT_MCP_REGISTERED:+$ADOPT_MCP_REGISTERED }context7" ;; esac' case_B3 "Context7: an attempt the receipt does not show is claimed"
mutant MB4 "$AM" '# BL-318-G6-MCP-REG-Q' '    case " $added " in *" qdrant "*) ADOPT_MCP_REGISTERED="${ADOPT_MCP_REGISTERED:+$ADOPT_MCP_REGISTERED }qdrant" ;; esac' case_B3 "Qdrant: an attempt the receipt does not show is claimed"
mutant MB5 "$ACO" '# BL-318-G6-OUTSIDE-IF' '  return 0' case_B1 "the refusal never names what the run registered (the dogfood shape)"
mutant MB6 "$ACO" '# BL-318-G6-OUTSIDE-IF' '  return 0' case_B5 "a BLOCKED refusal never names it"
mutant MB7 "$ACO" '# BL-318-G6-NOTHING-LINE' '    printf '"'"'          %s did not begin. Nothing was committed and nothing was written.\n'"'"' "${ADOPT_OPERATION:-Adoption}" >&2' case_B2 "the refusal says nothing was written, without 'to this project'"
mutant MB8 "$ACO" '# BL-318-G6-NOTHING-BEGIN' '  if true; then' case_B1 "a run that registered a server still says adoption did not begin"
mutant MB9 "$ACO" '# BL-318-G6-OUTSIDE-NOTHING' '      :' case_B6 "the forced-block arm drops the registration note (review round 1, R-4)"
mutant MB10 "$ACO" '# BL-318-G6-OUTSIDE-BLOCKED' '    :' case_B5 "the arm for a touched project drops the registration note"
mutant MB11 "$ACO" '# BL-318-G6-BLOCK-LABEL' '  if [ "${ADOPT_FORCE_BLOCK:-0}" -eq 1 ] || [ "$_n" -gt 0 ] || adopt_has_touched_disk; then' case_B4 "a stop after a registration is labelled REFUSED again (review round 1, R-6)"
mutant MB12 "$ACO" '# BL-318-G6-NOTHING-ARM' '    if [ "${ADOPT_FORCE_BLOCK:-0}" -eq 1 ] && [ "$_n" -eq 0 ] && ! adopt_has_touched_disk && [ "${ADOPT_COMMITTED:-0}" -ne 1 ]; then' case_B4 "a block after a registration says the run ATTEMPTED writes to the project"
mutant MC1 "$A4" '# BL-242-ACT4-REFUSE-COMMIT' '    ( if (.adoptedAtCommit | type) != "string" or .adoptedAtCommit != $stamp then "adoptedAtCommit is not the commit this project was adopted at (\($stamp))" else empty end ),' case_C2 "the finisher says 'the commit this project was adopted at' again"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
