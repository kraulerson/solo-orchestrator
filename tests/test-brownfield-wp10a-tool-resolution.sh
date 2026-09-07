#!/usr/bin/env bash
# tests/test-brownfield-wp10a-tool-resolution.sh
#
# Brownfield adoption WP10a — TOOL RESOLUTION AT STEP 2, and §6.2's
# re-scan-after-install mechanic.
# Design: docs/designs/2026-08-23-brownfield-adoption-v2.md §6.2, §8.2 step 2,
# §10-WP10.
#
# ── WHAT THIS HALF IS, AND WHAT IT DELIBERATELY IS NOT ──────────────────────
# WP10 is built as two PRs. 10a runs the resolver and refreshes a stale
# secrets section; 10b brings §6.1's eight status×tier cells, §6.3's
# dispositions and §6.4's tiered escape. **10a therefore changes NO
# stop/proceed decision** — a `tool-unavailable` report still completes an
# adoption here, exactly as it did before this package, and 10b is what makes
# it stop. Asserting otherwise in this file would pin behaviour the next PR is
# specified to change.
#
# ── THE ONE THING THAT MUST NEVER HAPPEN ───────────────────────────────────
# `install_cmd` IS NOT ALWAYS A COMMAND. Measured against the shipped matrix:
# on a darwin host WITH brew and without gitleaks the resolver returns
# `brew install gitleaks`; with brew ALSO absent it returns the matrix's
# `manual` fallback, which is the string
# `https://github.com/gitleaks/gitleaks/releases`. A build that pipes the
# bucket's `install_cmd` to a shell executes a URL. X2 pins that it does not.
#
# ── MUTATION HARNESS STANDARD (inherited from the WP9a/9b suites) ──────────
#   • anchored end-of-line markers, excised with `s|^.*MARKER$|…|`;
#   • the anchor asserted at sites==1 in its OWN shipped source;
#   • every mutant additionally asserts `bash -n`;
#   • a MODE-PRESERVING in-place edit;
#   • a FRESH fixture per scenario, from mktemp -d;
#   • mutants run against a framework MIRROR — the tree under test is never
#     edited, so a failure here cannot leave this repository mutated.
#
# Hermetic: temp dirs only, no network, no remote creation. The resolver is
# driven through `SOIF_ADOPT_RESOLVER` (a test seam, see below) so no test
# installs anything on the host running it.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"
LIB_DIR="$REPO_ROOT/scripts/lib/adopt"
L_STATE="$LIB_DIR/adopt-state.sh"
L_TOOLS="$LIB_DIR/adopt-tools.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

_tree_hash() {
  local p="$1"
  ( cd "$p" 2>/dev/null && find . -path ./.git -prune -o -type f -print 2>/dev/null \
      | LC_ALL=C sort \
      | while IFS= read -r f; do
          printf '%s ' "$f"
          (shasum -a 256 "$f" 2>/dev/null || sha256sum "$f" 2>/dev/null || printf 'nohash\n') | awk '{print $1}'
        done ) | (shasum -a 256 2>/dev/null || sha256sum 2>/dev/null) | awk '{print $1}'
}

if [ ! -f "$DRIVER" ]; then
  echo "  [FAIL] setup — $DRIVER not found"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "  [FAIL] setup — jq is required by this suite"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── Fixtures ────────────────────────────────────────────────────────────────
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" \
      && git init -q . \
      && git config user.email "wp10a@test.invalid" \
      && git config user.name  "WP10a Test" \
      && git config core.excludesFile /dev/null ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service and a postgres database.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

TEMPLATE="$(newtmp)/template"
REPORT=""
REPORT_OK=0
if mk_adoptee "$TEMPLATE"; then
  if bash "$REPO_ROOT/scripts/scout.sh" --root "$TEMPLATE" --out "$TOPTMP/scan" >/dev/null 2>&1; then
    REPORT="$TOPTMP/scan/scout-report.json"
    [ -s "$REPORT" ] && REPORT_OK=1
  fi
fi
if [ "$REPORT_OK" -ne 1 ]; then
  echo "  [FAIL] setup — scripts/scout.sh produced no report"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── THE RESOLVER SEAM, and why the suite drives it rather than the real one ─
# The shipped resolver probes the HOST. A suite that let it do so would assert
# different things on a laptop with gitleaks and a runner without it — the
# local-vs-CI divergence CLAUDE.md documents at length — and, worse, the
# install arm would install software on whatever machine ran the tests.
# `SOIF_ADOPT_RESOLVER` names an alternative resolver executable; every case
# below points it at a stub emitting the exact JSON the real resolver was
# MEASURED to emit for that case (see the header). The seam is not asserted
# directly by any one case — a draft claimed X0 did that, and X0 only counts a
# marker in a different file. It is pinned INCIDENTALLY: disabling it so the
# real resolver runs reddens NINE assertions — X2b, X4, X5(linux), X5(brew),
# X6b, X7, X9, X9b and M2 — while X3's two SURVIVE.
#
# THIS NUMBER HAS BEEN WRONG TWICE AND THE SECOND TIME IS THE INSTRUCTIVE ONE.
# A draft enumerated "X2, X3, X4 and X5" and was wrong about X3. Its
# replacement said EIGHT — measured correctly, on the tree BEFORE X9b was
# narrowed in the same commit, and never re-run against the finished one. The
# fix that made X9b discriminate is precisely what added the ninth failure, so
# one fix invalidated another fix's number inside a single commit. Do not carry
# this figure forward: disable `_adopt_resolver_path`'s branch and count.
# _mk_resolver <path> <bucket> <install_cmd>  → 0 on a stub whose payload was
# VERIFIED to carry the command it was asked for.
#
# BUILT WITH `jq`, NOT `sed`, AND THAT IS THIS REPOSITORY'S OWN DOCUMENTED
# TRAP. A first cut interpolated $cmd into a `|`-delimited `sed` expression.
# The real gitleaks Linux recipe contains a shell pipe, so the expression died
# with `bad flag in substitute command` — and `_sed_inplace` returns 0
# unconditionally, so the builder reported success while emitting a stub with
# ALL FOUR BUCKETS EMPTY. Every case then exercised the "matrix named nothing"
# arm, the absence assertions still printed PASS, and the real recipe was never
# tested once. CLAUDE.md says it in as many words: "assert the edit actually
# applied, because 'sed ran' is not 'sed edited'." This asserts the payload.
_mk_resolver() {
  local out="$1" bucket="$2" cmd="$3" tool="${4:-gitleaks}" payload=""
  case "$bucket" in
    already)
      payload="$(jq -n --arg t "$tool" '{already_installed: [{name: $t, version: "8.30.1", category: "Secret Detection"}], auto_install: [], manual_install: [], deferred: []}')" ;;
    auto)
      payload="$(jq -n --arg c "$cmd" --arg t "$tool" '{already_installed: [], auto_install: [{name: $t, category: "Secret Detection", install_cmd: $c, install_cmds: [$c]}], manual_install: [], deferred: []}')" ;;
    manual)
      # THE REAL RESOLVER WRITES `instructions` HERE, NOT `install_cmd`
      # (`--arg instructions "$INSTALL_CMD"` … `{name, category, instructions,
      # required, description}`). A stub emitting `install_cmd` in this bucket
      # is a shape the resolver cannot produce, and a driver read against it
      # proves nothing about the real one.
      payload="$(jq -n --arg c "$cmd" --arg t "$tool" '{already_installed: [], auto_install: [], manual_install: [{name: $t, category: "Secret Detection", instructions: $c, required: true}], deferred: []}')" ;;
    *) return 1 ;;
  esac
  [ -n "$payload" ] || return 1
  {
    printf '#!/usr/bin/env bash\n'
    printf '# A stub standing in for scripts/resolve-tools.sh. Ignores its arguments.\n'
    printf 'cat <<%s\n' "'RESOLVERJSON'"
    printf '%s\n' "$payload"
    printf 'RESOLVERJSON\n'
  } > "$out"
  chmod +x "$out"

  # THE ASSERTION THE FIRST CUT LACKED: run the stub and require the payload to
  # parse AND to carry the command asked for. A builder that silently produced
  # an empty stub is worse than one that failed.
  local got
  got="$( "$out" 2>/dev/null | jq -e . >/dev/null 2>&1 && "$out" 2>/dev/null )" || return 1
  [ -n "$got" ] || return 1
  if [ -n "$cmd" ]; then
    printf '%s' "$got" | jq -e --arg c "$cmd" \
      '[.auto_install[]?.install_cmd, .manual_install[]?.instructions] | any(. == $c)' >/dev/null 2>&1 || return 1
  fi
  return 0
}

# Five answers: the tier question plus this report's four scan-derived
# confirmations. A case that adds the install question passes six.
_ans() { local tier="${1:-1}"; printf '%s\n1\n1\n1\n1\n' "$tier"; }
_ans_install() { local tier="${1:-1}" install="${2:-2}"; printf '%s\n%s\n1\n1\n1\n1\n' "$tier" "$install"; }

RUN_RC=0; RUN_OUT=""; RUN_ERR=""
run_adopt() {   # run_adopt <dir> <answers> <report> [fw] [extra env assignments...]
  local dir="$1" answers="$2" report="$3" fw="${4:-$REPO_ROOT}"; shift 4 2>/dev/null || shift 3
  RUN_RC=0
  RUN_OUT="$(dirname "$answers")/run-out"
  RUN_ERR="$(dirname "$answers")/run-err"
  ( cd "$dir" && env "$@" bash "$fw/scripts/adopt-project.sh" --scan-report "$report" ) \
    < "$answers" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  return 0
}

mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$m/" || return 1
  cp -Rp "$REPO_ROOT/templates" "$m/" || return 1
  cp -p "$REPO_ROOT/init.sh" "$m/" || return 1
  return 0
}

_mutate() {   # _mutate <mirror> <lib> <marker> <replacement>
  local mir="$1" lib="$2" mark="$3" repl="$4" before after changed
  before="$(mktemp)"; cp "$mir/scripts/lib/adopt/$lib" "$before"
  _sed_inplace "$mir/scripts/lib/adopt/$lib" "s|^.*${mark}\$|${repl}|"
  after="$mir/scripts/lib/adopt/$lib"
  changed="$(_changed_lines "$before" "$after")"
  rm -f "$before"
  [ "$changed" -ge 2 ] || { printf '0\n'; return 0; }
  [ "$(_parses "$after")" = "1" ] || { printf '0\n'; return 0; }
  printf '1\n'
}

echo "=== X — the resolver runs at step 2, and never executes a non-command ==="

X0_MARK="# BL-242-RESOLVER-CALL"
x0_sites="$(_sites "$L_STATE" "$X0_MARK")"
[ "$x0_sites" = "1" ] \
  && pass "X0 — '$X0_MARK' occurs exactly once at end-of-line in adopt-state.sh" \
  || fail_ "X0" "'$X0_MARK' occurs $x0_sites times (need exactly 1)"

# X1 — the common case: the scanner is already there, so nothing is asked and
# nothing is installed. The POSITIVE half matters as much as the absence: a
# build that skipped resolution entirely would also ask nothing.
X1="$(newtmp)"
mkdir -p "$X1/p"
if ! mk_adoptee "$X1/p"; then
  fail_ "X1 setup" "could not build the adoptee"
else
  _mk_resolver "$X1/resolver" already "" || fail_ "X1 setup" "the resolver stub did not build"
  _ans 1 > "$X1/answers"
  run_adopt "$X1/p" "$X1/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X1/resolver"
  X1_RC="$RUN_RC"
  [ "$X1_RC" -eq 0 ] \
    && pass "X1 — with the scanner already present the adoption completes (rc 0)" \
    || fail_ "X1" "adoption refused (rc $X1_RC) when the scanner was already installed"
  if grep -qi 'secret.detection\|gitleaks' "$RUN_OUT" 2>/dev/null; then
    pass "X1b — the run SAYS it resolved the scanner (the resolver actually ran)"
  else
    fail_ "X1b" "no sign the resolver ran; X1's silence proves nothing"
  fi
  if grep -q 'Set .* up now?' "$RUN_OUT" 2>/dev/null; then
    fail_ "X1c" "the operator was asked to set up a tool that is already present"
  else
    pass "X1c — no install question is asked in the common case"
  fi
fi

# X2 — THE ONE THAT MUST NEVER HAPPEN. `install_cmd` is the matrix's `manual`
# fallback, a URL. It must not be executed, and the operator must be told.
X2="$(newtmp)"
mkdir -p "$X2/p"
if ! mk_adoptee "$X2/p"; then
  fail_ "X2 setup" "could not build the adoptee"
else
  # a URL that would create this file if it were ever passed to a shell
  X2_CANARY="$X2/EXECUTED"
  _mk_resolver "$X2/resolver" manual "https://github.com/gitleaks/gitleaks/releases; touch $X2_CANARY" \
    || fail_ "X2 setup" "the resolver stub did not build"
  _ans 1 > "$X2/answers"
  run_adopt "$X2/p" "$X2/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X2/resolver"
  [ ! -e "$X2_CANARY" ] \
    && pass "X2 — a manual-bucket install_cmd is NEVER executed (the canary was not created)" \
    || fail_ "X2" "the install_cmd was piped to a shell — a URL from the tool matrix got executed"
  if grep -qi 'install it yourself\|cannot install it for you' "$RUN_OUT" 2>/dev/null; then
    pass "X2b — the operator is told to install it themselves, with the reference"
  else
    fail_ "X2b" "the run went silent about a scanner it could not install"
  fi
fi

# X3 — the install question, and DECLINING it. Nothing is executed, and the
# adoption still completes: 10a changes no stop/proceed decision.
X3="$(newtmp)"
mkdir -p "$X3/p"
if ! mk_adoptee "$X3/p"; then
  fail_ "X3 setup" "could not build the adoptee"
else
  X3_CANARY="$X3/INSTALLED"
  _mk_resolver "$X3/resolver" auto "touch $X3_CANARY" || fail_ "X3 setup" "the resolver stub did not build"
  _ans_install 1 2 > "$X3/answers"      # 2 = do not install
  run_adopt "$X3/p" "$X3/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X3/resolver"
  X3_RC="$RUN_RC"
  [ ! -e "$X3_CANARY" ] \
    && pass "X3 — declining the install runs nothing" \
    || fail_ "X3" "the install command ran even though the operator declined"
  [ "$X3_RC" -eq 0 ] \
    && pass "X3b — and the adoption still completes (rc 0): 10a changes no stop/proceed decision" \
    || fail_ "X3b" "declining the install refused the adoption (rc $X3_RC) — that is 10b's decision, not 10a's"
fi

# X4 — ACCEPTING it. The command runs, once.
X4="$(newtmp)"
mkdir -p "$X4/p"
if ! mk_adoptee "$X4/p"; then
  fail_ "X4 setup" "could not build the adoptee"
else
  X4_CANARY="$X4/INSTALLED"
  _mk_resolver "$X4/resolver" auto "touch $X4_CANARY" || fail_ "X4 setup" "the resolver stub did not build"
  _ans_install 1 1 > "$X4/answers"      # 1 = install it now
  run_adopt "$X4/p" "$X4/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X4/resolver"
  [ -e "$X4_CANARY" ] \
    && pass "X4 — accepting the install runs the resolver's own command" \
    || fail_ "X4" "the operator accepted and nothing ran"
fi

# ── X5 — THE REAL RECIPES, in both directions. ─────────────────────────────
# The only "runnable" fixture above is `touch <path>`, a shape no matrix entry
# has. These two are the SHIPPED strings, measured from the real resolver:
# darwin+brew yields `brew install gitleaks`; linux+apt/dnf/pacman yields the
# array joined with ` && `, whose first token is `GITLEAKS_VERSION=$(curl`.
# A first cut resolved that first token as a command and therefore REFUSED the
# only Linux install path the matrix has — telling the operator "this host has
# no package manager recipe for it" while printing that recipe.
X5_LINUX='GITLEAKS_VERSION=$(curl -sSf https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r .tag_name) && curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/x.tar.gz" | sudo tar -xz -C /usr/local/bin gitleaks'
X5_BREW='brew install gitleaks'
X5_URL='https://github.com/gitleaks/gitleaks/releases'

for _case in "linux:$X5_LINUX:accept" "brew:$X5_BREW:accept" "url:$X5_URL:refuse"; do
  _label="${_case%%:*}"; _rest="${_case#*:}"; _cmd="${_rest%:*}"; _want="${_rest##*:}"
  X5D="$(newtmp)"; mkdir -p "$X5D/p"
  if ! mk_adoptee "$X5D/p"; then
    fail_ "X5 setup ($_label)" "could not build the adoptee"
    continue
  fi
  # The stub carries the REAL string. The builder now asserts its own payload,
  # so a shell pipe in the recipe can no longer silently empty it.
  if ! _mk_resolver "$X5D/resolver" auto "$_cmd"; then
    fail_ "X5 ($_label)" "the resolver stub did not build with the real recipe — the builder ate it"
    continue
  fi
  _ans_install 1 2 > "$X5D/answers"     # decline: this asserts CLASSIFICATION, not installation
  run_adopt "$X5D/p" "$X5D/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X5D/resolver"
  _asked=0
  grep -q 'This would run, exactly as written' "$RUN_OUT" 2>/dev/null && _asked=1
  case "$_want" in
    accept)
      [ "$_asked" -eq 1 ] \
        && pass "X5 ($_label) — the shipped recipe is offered to the operator" \
        || fail_ "X5 ($_label)" "the real recipe was refused as un-runnable; on this host adoption can never install the scanner" ;;
    refuse)
      [ "$_asked" -eq 0 ] \
        && pass "X5 ($_label) — a URL is never offered as something to run" \
        || fail_ "X5 ($_label)" "a URL was offered to the operator as a command" ;;
  esac
done

# ── X6 — THE INSTALLER MUST NOT WRITE INTO THE OPERATOR'S REPOSITORY. ──────
# `eval` inherits the adoptee's directory as cwd, so a recipe writing a
# relative path writes into their repo — and `adopt_refuse` then says "nothing
# was written". Measured before the fix: two untracked files left behind under
# exactly that refusal. Real matrix recipes write relative paths.
X6="$(newtmp)"
mkdir -p "$X6/p"
if ! mk_adoptee "$X6/p"; then
  fail_ "X6 setup" "could not build the adoptee"
elif ! _mk_resolver "$X6/resolver" auto "touch INSTALLER_WROTE_HERE"; then
  fail_ "X6 setup" "the resolver stub did not build"
else
  _ans_install 1 1 > "$X6/answers"      # accept: the command must RUN, somewhere
  run_adopt "$X6/p" "$X6/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X6/resolver"
  [ ! -e "$X6/p/INSTALLER_WROTE_HERE" ] \
    && pass "X6 — an installer writing a RELATIVE path does not write into the adoptee" \
    || fail_ "X6" "the install ran with the operator's repository as its working directory"
  # …and the driver admits the host may have been touched, rather than
  # claiming otherwise on a later refusal.
  if grep -q 'is installed and on PATH\|did not put' "$RUN_OUT" 2>/dev/null; then
    pass "X6b — the run reports what the install actually achieved"
  else
    fail_ "X6b" "the install arm said nothing about its outcome"
  fi
fi

# ── X7 — "installed" IS VERIFIED, NOT ASSERTED. ────────────────────────────
# A recipe whose last stage exits 0 without putting anything on PATH must not
# produce a success claim. `true` is that recipe.
X7="$(newtmp)"
mkdir -p "$X7/p"
if ! mk_adoptee "$X7/p"; then
  fail_ "X7 setup" "could not build the adoptee"
elif ! _mk_resolver "$X7/resolver" auto "true" "gitleaks-wp10a-absent"; then
  fail_ "X7 setup" "the resolver stub did not build"
else
  # THE TOOL NAME IS ONE THAT CANNOT EXIST, ON ANY HOST. A first cut named
  # `gitleaks` and so took the "already present" branch on this laptop and the
  # "absent" branch on a runner — asserting different things in the two places,
  # which is the local-vs-CI divergence CLAUDE.md documents. Worse, it made the
  # assertion VACUOUS here: the mutant that replaces the probe with `true`
  # survived, because the probe was going to succeed anyway.
  if command -v gitleaks-wp10a-absent >/dev/null 2>&1; then
    fail_ "X7ctl" "a tool named gitleaks-wp10a-absent exists on this host; pick another name"
  else
    pass "X7ctl — the fixture names a tool that is absent on every host, so the probe must fail"
    _ans_install 1 1 > "$X7/answers"
    run_adopt "$X7/p" "$X7/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X7/resolver"
    if grep -q 'did not put gitleaks-wp10a-absent on PATH' "$RUN_OUT" 2>/dev/null; then
      pass "X7 — a recipe exiting 0 without installing anything does NOT produce a success claim"
    else
      fail_ "X7" "a recipe that installed nothing was reported as installed"
    fi
  fi
fi

# ── X8 — THE BUCKET BRANCH, with a payload the URL test cannot refuse. ────
# `in_manual` is the "primary classifier", and every manual-bucket fixture in
# this file carries a URL — which the syntactic backstop refuses on its own. So
# the bucket branch was DEAD CODE under test: review deleted it and the whole
# suite stayed green. It matters forward, not just now: the resolver fix filed
# on `## BL-242:` is exactly what starts routing real recipes into
# `manual_install`, and the branch would ship into that world untested.
#
# The payload here is a RUNNABLE command in the manual bucket — a shape the
# resolver produces the moment `manual` leaves its `INSTALL_KEYS`.
X8="$(newtmp)"
mkdir -p "$X8/p"
if ! mk_adoptee "$X8/p"; then
  fail_ "X8 setup" "could not build the adoptee"
else
  X8_CANARY="$X8/EXECUTED"
  if ! _mk_resolver "$X8/resolver" manual "touch $X8_CANARY"; then
    fail_ "X8 setup" "the resolver stub did not build"
  else
    _ans 1 > "$X8/answers"
    run_adopt "$X8/p" "$X8/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X8/resolver"
    [ ! -e "$X8_CANARY" ] \
      && pass "X8 — a RUNNABLE command in the manual bucket is still never executed (the bucket decides, not the string)" \
      || fail_ "X8" "the manual bucket was ignored because the payload looked runnable"
    if grep -q 'This would run, exactly as written' "$RUN_OUT" 2>/dev/null; then
      fail_ "X8b" "a manual-bucket entry was offered to the operator as something to run"
    else
      pass "X8b — and it is not offered as something to run"
    fi
  fi
fi

# ── X9 — THE HONESTY FLAG, pinned by the sentence it changes. ─────────────
# `adopt_touched_disk` before the eval is half of round 1's blocker fix, and
# review excised it with the whole suite staying green. Its whole purpose is
# what a LATER refusal says, so that is what this asserts: accept the install,
# then answer something invalid, and read the refusal.
X9="$(newtmp)"
mkdir -p "$X9/p"
if ! mk_adoptee "$X9/p"; then
  fail_ "X9 setup" "could not build the adoptee"
elif ! _mk_resolver "$X9/resolver" auto "true" "gitleaks-wp10a-absent"; then
  fail_ "X9 setup" "the resolver stub did not build"
else
  # tier, accept the install, then an answer that is not on offer
  printf '1\n1\nNOT-AN-OPTION\n' > "$X9/answers"
  run_adopt "$X9/p" "$X9/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X9/resolver"
  X9_ALL="$(cat "$RUN_ERR" "$RUN_OUT" 2>/dev/null)"
  case "$X9_ALL" in
    *"Nothing was committed and nothing was written"*)
      fail_ "X9" "after running an installer the refusal still claims nothing was written" ;;
    *)
      pass "X9 — after an install attempt the refusal no longer claims nothing was written" ;;
  esac
  # `*ATTEMPTED*` ALONE. A first cut also accepted `*"already"*`, which the
  # reverse-intake preamble prints on EVERY adoption ("Some of this the scan
  # already answered…") — so X9b passed unconditionally, including over a run
  # whose refusal read "Nothing was committed and nothing was written", the
  # exact sentence it exists to detect the absence of. Proven by mutation: with
  # `adopt_touched_disk` excised, X9 went red and X9b stayed green.
  case "$X9_ALL" in
    *ATTEMPTED*)
      pass "X9b — it says an attempt was made against this project" ;;
    *)
      fail_ "X9b" "the refusal went quiet about the install attempt" ;;
  esac
fi

# ── X10 — AN INSTALLER MUST NOT EAT THE OPERATOR'S ANSWERS. ───────────────
# The eval inherits fd 0, the same open file description the driver reads
# answers from, so a recipe that reads stdin CONSUMES THEM. Measured before the
# fix with a recipe of `read a; read b`: two confirmations swallowed and the
# adoption then aborted for want of answers. Latent with today's matrix and
# live the moment an eval-reachable recipe prompts.
X10="$(newtmp)"
mkdir -p "$X10/p"
if ! mk_adoptee "$X10/p"; then
  fail_ "X10 setup" "could not build the adoptee"
elif ! _mk_resolver "$X10/resolver" auto "read _a; read _b; true" "gitleaks-wp10a-absent"; then
  fail_ "X10 setup" "the resolver stub did not build"
else
  # tier + accept the install + the four scan-derived confirmations. If the
  # installer eats any of them the run cannot complete.
  printf '1\n1\n1\n1\n1\n1\n' > "$X10/answers"
  run_adopt "$X10/p" "$X10/answers" "$REPORT" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X10/resolver"
  X10_RC="$RUN_RC"
  [ "$X10_RC" -eq 0 ] \
    && pass "X10 — a stdin-reading installer does not consume the operator's answers (rc 0)" \
    || fail_ "X10" "the adoption failed (rc $X10_RC) because the installer read from the answer stream"
fi

# ── X11 — A COMPLETED SCAN MUST NEVER BE DISCARDED IN SILENCE. ────────────
# The splice can fail on a report that is not valid JSON — `adopt_obtain_report`
# only checks that the file exists. A first cut had no `else` there, so a scan
# that RAN (measured: 755 bytes of refreshed section) was thrown away and the
# run said nothing, leaving the operator reading the survey's stale answer.
X11="$(newtmp)"
mkdir -p "$X11/p"
if ! mk_adoptee "$X11/p"; then
  fail_ "X11 setup" "could not build the adoptee"
else
  printf 'this is not json at all\n' > "$X11/report.json"
  _mk_resolver "$X11/resolver" already "" || fail_ "X11 setup" "the resolver stub did not build"
  _ans 1 > "$X11/answers"
  run_adopt "$X11/p" "$X11/answers" "$X11/report.json" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$X11/resolver"
  X11_ALL="$(cat "$RUN_OUT" "$RUN_ERR" 2>/dev/null)"
  # `"could not be merged"` ALONE. THREE of the FOUR sibling failure arms say
  # "could not be re-run" (the fourth says "could not be rendered"; the fifth
  # exit is the deliberate don't-rescan skip, which is not a failure arm and
  # prints nothing) — so accepting that phrase made X11 pass over runs where no
  # scan happened at all, weaker than its own name. Derived, not counted from
  # memory: `grep -c 'could not be re-run' scripts/lib/adopt/adopt-tools.sh` = 3. (Those faults are
  # caught by R1/R3b/M4; this assertion is about the SIXTH arm specifically.)
  case "$X11_ALL" in
    *"could not be merged"*)
      pass "X11 — an unmergeable re-scan SAYS so rather than discarding the result silently" ;;
    *)
      fail_ "X11" "the re-scan result was discarded with no word to the operator" ;;
  esac
fi

echo ""
echo "=== R — §6.2's re-scan, and its converse ==="

R_MARK="# BL-242-SECRETS-RESCAN"
r_sites="$(_sites "$L_TOOLS" "$R_MARK")"
[ "$r_sites" = "1" ] \
  && pass "R0 — '$R_MARK' occurs exactly once at end-of-line in adopt-tools.sh" \
  || fail_ "R0" "'$R_MARK' occurs $r_sites times (need exactly 1)"

# A report whose secrets section says the scanner was never there — exactly
# what §6.2 says Act 2 may be handed, because Scout can predate the install.
_stale_report() {   # _stale_report <dest>
  jq '.secrets.status = "tool-unavailable"
      | .secrets.findingCount = 0
      | .secrets.findings = []
      | .secrets.note = "gitleaks is not installed, so NOTHING WAS SCANNED."' \
     "$REPORT" > "$1" 2>/dev/null
}

R1="$(newtmp)"
mkdir -p "$R1/p"
if ! mk_adoptee "$R1/p" || ! _stale_report "$R1/report.json"; then
  fail_ "R1 setup" "could not build the adoptee or the stale report"
else
  R1_BEFORE="$(jq -r '.secrets.status' "$R1/report.json" 2>/dev/null)"
  [ "$R1_BEFORE" = "tool-unavailable" ] \
    && pass "R1ctl — the consumed report says tool-unavailable, so there is something to refresh" \
    || fail_ "R1ctl" "the fixture report says '$R1_BEFORE'; this case tests nothing"
  _mk_resolver "$R1/resolver" already ""
  _ans 1 > "$R1/answers"
  run_adopt "$R1/p" "$R1/answers" "$R1/report.json" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$R1/resolver"
  R1_AFTER="$(jq -r '.secrets.status // ""' "$R1/p/.claude/adoption/scout-report.json" 2>/dev/null)"
  [ "$R1_AFTER" = "scanned" ] \
    && pass "R1 — the PERSISTED report says 'scanned': Act 2 re-scanned rather than trusting a stale 'nobody looked'" \
    || fail_ "R1" "the persisted report still says '$R1_AFTER' — the re-scan did not happen or did not land"
fi

# R2 — THE CONVERSE, and it is what stops the re-scan being unconditional. A
# report that already says `scanned` is the one Act 2 acted on; re-running the
# scanner would discard the evidence hash the stamp records and cost a full
# history walk for nothing.
R2="$(newtmp)"
mkdir -p "$R2/p"
if ! mk_adoptee "$R2/p"; then
  fail_ "R2 setup" "could not build the adoptee"
else
  # a sentinel the re-scan would necessarily overwrite
  jq '.secrets.note = "SENTINEL-DO-NOT-RESCAN"' "$REPORT" > "$R2/report.json" 2>/dev/null
  _mk_resolver "$R2/resolver" already ""
  _ans 1 > "$R2/answers"
  run_adopt "$R2/p" "$R2/answers" "$R2/report.json" "$REPO_ROOT" "SOIF_ADOPT_RESOLVER=$R2/resolver"
  R2_NOTE="$(jq -r '.secrets.note // ""' "$R2/p/.claude/adoption/scout-report.json" 2>/dev/null)"
  case "$R2_NOTE" in
    *SENTINEL-DO-NOT-RESCAN*)
      pass "R2 — an already-scanned report is NOT re-scanned (its own note survives)" ;;
    *)
      fail_ "R2" "the secrets section was rewritten on a report that was already 'scanned'" ;;
  esac
fi

# ── R3 — THE ATTESTATION TRACKS THE RESULT, NOT THE SPLICE. ───────────────
# A first cut printed "this project's history was read rather than skipped"
# whenever the splice succeeded — including when the refreshed status was
# still `tool-unavailable`, three lines after saying the scanner could not be
# installed. A false all-clear on a security surface.
R3="$(newtmp)"
mkdir -p "$R3/p"
if ! mk_adoptee "$R3/p" || ! _stale_report "$R3/report.json"; then
  fail_ "R3 setup" "could not build the adoptee or the stale report"
elif ! _mk_resolver "$R3/resolver" manual "$X5_URL"; then
  fail_ "R3 setup" "the resolver stub did not build"
else
  # Force the re-scan to come back tool-unavailable by pointing Scout's own
  # seam at a binary that does not exist — the mechanism scout-secrets.sh
  # documents for exactly this.
  _ans 1 > "$R3/answers"
  run_adopt "$R3/p" "$R3/answers" "$R3/report.json" "$REPO_ROOT" \
    "SOIF_ADOPT_RESOLVER=$R3/resolver" "SCOUT_GITLEAKS_BIN=gitleaks-does-not-exist-wp10a"
  R3_STATUS="$(jq -r '.secrets.status // ""' "$R3/p/.claude/adoption/scout-report.json" 2>/dev/null)"
  if [ "$R3_STATUS" = "tool-unavailable" ]; then
    pass "R3ctl — the re-scan still could not look, so the attestation is under test"
    if grep -q "history[[:space:]]*$" "$RUN_OUT" 2>/dev/null && grep -q 'was read\.' "$RUN_OUT" 2>/dev/null; then
      fail_ "R3" "the run said the history WAS READ over a record saying nothing was scanned"
    else
      pass "R3 — it does not claim the history was read"
    fi
    if grep -q 'STILL could not look' "$RUN_OUT" 2>/dev/null; then
      pass "R3b — and it says plainly that nothing is known"
    else
      fail_ "R3b" "the run went quiet about a re-scan that found nothing to look with"
    fi
  else
    fail_ "R3ctl" "the re-scan produced '$R3_STATUS'; this case cannot test the attestation"
  fi
fi

echo ""
echo "=== M — the mutation proofs ==="

# M1 — drop the resolver call.
M1="$(newtmp)"
mkdir -p "$M1/fw" "$M1/p"
if ! mk_mirror "$M1/fw"; then
  fail_ "M1 setup" "could not mirror the framework"
elif [ "$(_mutate "$M1/fw" "adopt-state.sh" "$X0_MARK" "  :")" != "1" ]; then
  fail_ "M1 setup" "the resolver-call mutation did not apply cleanly"
elif ! mk_adoptee "$M1/p"; then
  fail_ "M1 setup" "could not build the adoptee"
else
  _mk_resolver "$M1/resolver" already ""
  _ans 1 > "$M1/answers"
  run_adopt "$M1/p" "$M1/answers" "$REPORT" "$M1/fw" "SOIF_ADOPT_RESOLVER=$M1/resolver"
  if grep -qi 'secret.detection\|gitleaks' "$RUN_OUT" 2>/dev/null; then
    fail_ "M1 (MUTATION)" "dropping the resolver call changed nothing observable"
  else
    pass "M1 (MUTATION) — dropping the call removes every sign the resolver ran: X1b is what pins it"
  fi
fi

# M2 — execute the manual-bucket command. THE CANARY IS THE ASSERTION.
M2="$(newtmp)"
mkdir -p "$M2/fw" "$M2/p"
M2_MARK="# BL-242-RESOLVER-NO-EXEC"
m2_sites="$(_sites "$L_TOOLS" "$M2_MARK")"
[ "$m2_sites" = "1" ] \
  && pass "M2-anchor — '$M2_MARK' occurs exactly once at end-of-line" \
  || fail_ "M2-anchor" "'$M2_MARK' occurs $m2_sites times (need exactly 1)"
if ! mk_mirror "$M2/fw"; then
  fail_ "M2 setup" "could not mirror the framework"
elif [ "$(_mutate "$M2/fw" "adopt-tools.sh" "$M2_MARK" "  if false; then")" != "1" ]; then
  fail_ "M2 setup" "the no-exec mutation did not apply cleanly"
elif ! mk_adoptee "$M2/p"; then
  fail_ "M2 setup" "could not build the adoptee"
else
  M2_CANARY="$M2/EXECUTED"
  _mk_resolver "$M2/resolver" manual "https://example.invalid/x; touch $M2_CANARY"
  _ans_install 1 1 > "$M2/answers"
  run_adopt "$M2/p" "$M2/answers" "$REPORT" "$M2/fw" "SOIF_ADOPT_RESOLVER=$M2/resolver"
  [ -e "$M2_CANARY" ] \
    && pass "M2 (MUTATION) — without the guard the manual-bucket string IS executed: X2 is what stops it" \
    || fail_ "M2 (MUTATION)" "removing the guard changed nothing — X2 may be passing for another reason"
fi

# M3 — drop the re-scan.
M3="$(newtmp)"
mkdir -p "$M3/fw" "$M3/p"
if ! mk_mirror "$M3/fw"; then
  fail_ "M3 setup" "could not mirror the framework"
elif [ "$(_mutate "$M3/fw" "adopt-tools.sh" "$R_MARK" "  return 0")" != "1" ]; then
  fail_ "M3 setup" "the re-scan mutation did not apply cleanly"
elif ! mk_adoptee "$M3/p" || ! _stale_report "$M3/report.json"; then
  fail_ "M3 setup" "could not build the adoptee or the stale report"
else
  _mk_resolver "$M3/resolver" already ""
  _ans 1 > "$M3/answers"
  run_adopt "$M3/p" "$M3/answers" "$M3/report.json" "$M3/fw" "SOIF_ADOPT_RESOLVER=$M3/resolver"
  M3_AFTER="$(jq -r '.secrets.status // ""' "$M3/p/.claude/adoption/scout-report.json" 2>/dev/null)"
  [ "$M3_AFTER" = "tool-unavailable" ] \
    && pass "M3 (MUTATION) — without the re-scan the stale 'tool-unavailable' is persisted verbatim: R1 is what refreshes it" \
    || fail_ "M3 (MUTATION)" "the persisted status is '$M3_AFTER' — the mutation changed nothing"
fi

# M4 — THE OPPOSITE DIRECTION ON THE SAME LINE, and one marker earns both.
# M3 turns the guard into an unconditional return (no re-scan ever); M4 removes
# the guard entirely (re-scan always). A build with only M3 would be satisfied
# by a re-scan that runs on every report, which discards the very measurement
# the adoption stamp is about to record a hash of.
M4="$(newtmp)"
mkdir -p "$M4/fw" "$M4/p"
if ! mk_mirror "$M4/fw"; then
  fail_ "M4 setup" "could not mirror the framework"
elif [ "$(_mutate "$M4/fw" "adopt-tools.sh" "$R_MARK" "  :")" != "1" ]; then
  fail_ "M4 setup" "the unconditional-rescan mutation did not apply cleanly"
elif ! mk_adoptee "$M4/p"; then
  fail_ "M4 setup" "could not build the adoptee"
else
  jq '.secrets.note = "SENTINEL-DO-NOT-RESCAN"' "$REPORT" > "$M4/report.json" 2>/dev/null
  _mk_resolver "$M4/resolver" already ""
  _ans 1 > "$M4/answers"
  run_adopt "$M4/p" "$M4/answers" "$M4/report.json" "$M4/fw" "SOIF_ADOPT_RESOLVER=$M4/resolver"
  M4_NOTE="$(jq -r '.secrets.note // ""' "$M4/p/.claude/adoption/scout-report.json" 2>/dev/null)"
  case "$M4_NOTE" in
    *SENTINEL-DO-NOT-RESCAN*)
      fail_ "M4 (MUTATION)" "removing the guard changed nothing — R2 may be passing for another reason" ;;
    *)
      pass "M4 (MUTATION) — without the guard an already-scanned report IS re-scanned: R2 is what stops it" ;;
  esac
fi

echo "=== S — the fast path: a scanner already on the host costs no resolver run ==="

# `## BL-251:` — WP10a spawned scripts/resolve-tools.sh on EVERY adoption,
# unconditionally, before inspecting anything: 6.8s wall per invocation, and
# the matrix's own gitleaks predicate is literally `command -v gitleaks`, so
# the expensive subprocess was being paid to learn what one builtin already
# knows. These cases pin the short-circuit AND the seam that keeps it out of
# the other eighteen cases' way.
#
# THE OBVIOUS PLACEMENT IS WRONG AND THAT IS WHY THE SEAM ARM EXISTS. Hoisting
# a bare `command -v gitleaks` to the top of adopt_resolve_tools puts a HOST
# PROBE ABOVE `SOIF_ADOPT_RESOLVER`; every stub-driven case above then stops
# reaching its stub. Measured with the seam arm neutered: ELEVEN failures on
# a host WITH gitleaks against FOUR on a host without — the delta is exactly
# X2b, X4, X5(linux), X5(brew), X6b, X7, X9, X9b and M2, the nine this file's
# header enumerates. FAILURE COUNTS AND NAMES ONLY: a passed-count written
# beside them went stale twice across tree changes while labelled "measured
# on this tree" — the exact failure mode the header above lectures about.
# The local-vs-CI divergence the seam comment was written to prevent. S2 is
# what keeps it fixed.
#
# DO NOT WRITE "34 / 0" HERE. An earlier draft did, in three places, meaning
# "the suite is host-independent without gitleaks". It is not: main's own
# 34-assertion suite measures 32 passed / 2 failed on a gitleaks-free host.
# R1 and R2 fail there through SCOUT, not through the resolver — a
# PRE-EXISTING host-dependence in a suite whose header claims the opposite.
# Recorded on `## BL-251:`; do not let a tidy tally hide it again.
#
# NEITHER CASE DEPENDS ON WHAT THIS HOST HAPPENS TO HAVE INSTALLED. A shim
# directory is PREPENDED to PATH so `command -v gitleaks` is true either way,
# and each case asserts the shim actually resolves before trusting the result.
# (Prepending is safe where CLAUDE.md's PATH-isolation warning is not: that
# trap is about a fixture that RE-ADDS the real PATH and so fails to remove a
# tool. This adds one.)

# _mk_gitleaks_shim <dir> → 0 if the shim is on PATH and resolves first
_mk_gitleaks_shim() {
  local d="$1"
  mkdir -p "$d" || return 1
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/gitleaks"
  chmod +x "$d/gitleaks" || return 1
  [ "$(PATH="$d:$PATH" command -v gitleaks 2>/dev/null)" = "$d/gitleaks" ] || return 1
  return 0
}

# _mk_sentinel_resolver <path> <sentinel> [bucket] → a resolver stub that
# RECORDS having been run and still emits a valid payload, so a case can tell
# "did not run" from "ran and broke".
#
# IT PROVES ITSELF, to the standard `_mk_resolver` above sets ("a builder that
# silently produced an empty stub is worse than one that failed"). A first cut
# checked only that the file was non-empty — so a stub whose sentinel path was
# unwritable ran, wrote nothing, and every "the resolver did not run" assertion
# printed PASS over a resolver that HAD run. Measured: builder rc=0, stub rc=0,
# sentinel absent, JSON valid. It now runs the stub once against a throwaway
# path and requires the sentinel to appear AND the payload to parse.
_mk_sentinel_resolver() {
  local out="$1" sentinel="$2" bucket="${3:-already}" payload probe
  case "$bucket" in
    already) payload="$(jq -nc '{already_installed: [{name: "gitleaks", version: "8.30.1", category: "Secret Detection"}], auto_install: [], manual_install: [], deferred: []}')" ;;
    auto)    payload="$(jq -nc '{already_installed: [], auto_install: [{name: "gitleaks", category: "Secret Detection", install_cmd: "true", install_cmds: ["true"]}], manual_install: [], deferred: []}')" ;;
    *) return 1 ;;
  esac
  [ -n "$payload" ] || return 1
  # THE SELF-TEST PROBES THE SENTINEL'S OWN DIRECTORY, not the stub's. A cut
  # that probed `dirname "$out"` proved the wrong directory writable: in every
  # real case those differ (the stub lives under fw/scripts, the sentinel under
  # the case root), so a sentinel in a nonexistent directory still produced
  # builder rc=0, stub rc=0, no sentinel, valid JSON — the false negative,
  # intact. Measured.
  probe="${sentinel}.selftest"
  {
    printf '#!/usr/bin/env bash\n'
    printf ': > "${SENTINEL_PATH:-%s}"\n' "$sentinel"
    printf 'cat <<%s\n' "'RESOLVERJSON'"
    printf '%s\n' "$payload"
    printf 'RESOLVERJSON\n'
  } > "$out"
  chmod +x "$out"
  rm -f "$probe" 2>/dev/null
  SENTINEL_PATH="$probe" "$out" 2>/dev/null | jq -e . >/dev/null 2>&1 || return 1
  [ -e "$probe" ] || return 1
  rm -f "$probe" 2>/dev/null
  return 0
}

# ── S1 — PRODUCTION SHAPE: seam UNSET, scanner present, resolver must not run.
# The framework is mirrored and its OWN scripts/resolve-tools.sh replaced, so
# `_adopt_resolver_path`'s default branch is the one under test — this is the
# path a real operator takes, not a seam-driven approximation.
S1="$(newtmp)"
mkdir -p "$S1/fw" "$S1/p" "$S1/bin"
if ! mk_mirror "$S1/fw"; then
  fail_ "S1 setup" "could not mirror the framework"
elif ! _mk_gitleaks_shim "$S1/bin"; then
  fail_ "S1 setup" "the gitleaks shim did not resolve first on PATH"
elif ! _mk_sentinel_resolver "$S1/fw/scripts/resolve-tools.sh" "$S1/ran"; then
  fail_ "S1 setup" "the sentinel resolver did not build"
elif ! mk_adoptee "$S1/p"; then
  fail_ "S1 setup" "could not build the adoptee"
else
  _ans 1 > "$S1/answers"
  run_adopt "$S1/p" "$S1/answers" "$REPORT" "$S1/fw" "PATH=$S1/bin:$PATH"
  S1_RC="$RUN_RC"
  if [ -e "$S1/ran" ]; then
    fail_ "S1" "the resolver RAN even though gitleaks is on PATH — the fast path did not fire"
  else
    pass "S1 — a present scanner short-circuits: resolve-tools.sh was never spawned"
  fi
  [ "$S1_RC" -eq 0 ] \
    && pass "S1b — the adoption still completes (rc=0) on the fast path" \
    || fail_ "S1b" "adoption exited $S1_RC on the fast path"
  if grep -q "already installed" "$RUN_OUT" 2>/dev/null; then
    pass "S1c — the fast path still SAYS the scanner is present"
  else
    fail_ "S1c" "the fast path went silent about the scanner it found"
  fi
fi

# ── S2 — THE SEAM OUTRANKS THE HOST PROBE. With SOIF_ADOPT_RESOLVER set, the
# resolver runs even though gitleaks is on PATH. This is the assertion that
# stops the fast path from reaching past the seam and re-breaking the other
# eighteen cases; `# BL-251-PROBE-SEAM` is the line it pins.
S2="$(newtmp)"
mkdir -p "$S2/p" "$S2/bin"
if ! _mk_gitleaks_shim "$S2/bin"; then
  fail_ "S2 setup" "the gitleaks shim did not resolve first on PATH"
elif ! _mk_sentinel_resolver "$S2/resolver" "$S2/ran"; then
  fail_ "S2 setup" "the sentinel resolver did not build"
elif ! mk_adoptee "$S2/p"; then
  fail_ "S2 setup" "could not build the adoptee"
else
  _ans 1 > "$S2/answers"
  run_adopt "$S2/p" "$S2/answers" "$REPORT" "$REPO_ROOT" \
    "SOIF_ADOPT_RESOLVER=$S2/resolver" "PATH=$S2/bin:$PATH"
  if [ -e "$S2/ran" ]; then
    pass "S2 — a stubbed resolver still runs: the fast path sits BEHIND the seam"
  else
    fail_ "S2" "the fast path reached past SOIF_ADOPT_RESOLVER — every stub-driven case above is now host-dependent"
  fi
fi

# ── S3 — THE FAST PATH IS NOT A SHORTCUT PAST THE RE-SCAN. Skipping the
# resolver must not also skip `_adopt_rescan_secrets`; a degraded survey is
# exactly the state a present scanner exists to refresh.
S3="$(newtmp)"
mkdir -p "$S3/fw" "$S3/p" "$S3/bin"
if ! mk_mirror "$S3/fw"; then
  fail_ "S3 setup" "could not mirror the framework"
elif ! _mk_gitleaks_shim "$S3/bin"; then
  fail_ "S3 setup" "the gitleaks shim did not resolve first on PATH"
elif ! _mk_sentinel_resolver "$S3/fw/scripts/resolve-tools.sh" "$S3/ran"; then
  fail_ "S3 setup" "the sentinel resolver did not build"
elif ! mk_adoptee "$S3/p"; then
  fail_ "S3 setup" "could not build the adoptee"
else
  jq '.secrets.status = "tool-unavailable"' "$REPORT" > "$S3/report.json" 2>/dev/null
  _ans 1 > "$S3/answers"
  run_adopt "$S3/p" "$S3/answers" "$S3/report.json" "$S3/fw" "PATH=$S3/bin:$PATH"
  if grep -q "The scan was re-run" "$RUN_OUT" 2>/dev/null; then
    pass "S3 — the fast path still reaches the re-scan on a degraded survey"
  else
    fail_ "S3" "the fast path skipped the re-scan a degraded survey exists to trigger"
  fi
fi

# ── S4 — THE SCANNER-ABSENT BRANCH, which the first cut of this fix asserted
# NOWHERE. Every S/MS case above runs with gitleaks present, so neutering
# `# BL-251-PROBE-HOST` to `true` survived the whole suite AND every
# PR-blocking check — while making a gitleaks-free host print "Secret
# detection: already installed." and, three lines later, "the scanner is not
# installed." CI installs gitleaks unconditionally, so no required check could
# have seen it. `SOIF_ADOPT_SCANNER_BIN` makes absence assertable WITHOUT
# depending on what this host has, which a PATH-subtraction fixture cannot do
# safely (CLAUDE.md's PATH-isolation trap).
S4="$(newtmp)"
mkdir -p "$S4/fw" "$S4/p" "$S4/bin"
if ! mk_mirror "$S4/fw"; then
  fail_ "S4 setup" "could not mirror the framework"
elif ! _mk_gitleaks_shim "$S4/bin"; then
  fail_ "S4 setup" "the gitleaks shim did not resolve first on PATH"
elif ! _mk_sentinel_resolver "$S4/fw/scripts/resolve-tools.sh" "$S4/ran" auto; then
  fail_ "S4 setup" "the sentinel resolver did not build"
elif ! mk_adoptee "$S4/p"; then
  fail_ "S4 setup" "could not build the adoptee"
else
  # gitleaks IS on PATH (the shim). The probe is pointed at a name that is not,
  # so the case asserts the ABSENT branch on any host, in either direction.
  _ans_install 1 2 > "$S4/answers"
  run_adopt "$S4/p" "$S4/answers" "$REPORT" "$S4/fw" \
    "PATH=$S4/bin:$PATH" "SOIF_ADOPT_SCANNER_BIN=gitleaks-bl251-absent"
  if [ -e "$S4/ran" ]; then
    pass "S4 — an absent scanner still reaches the resolver: the fast path is not unconditional"
  else
    fail_ "S4" "the fast path fired with NO scanner present — the resolver was never consulted"
  fi
  if grep -q "already installed" "$RUN_OUT" 2>/dev/null; then
    fail_ "S4b" "a host with no scanner was told the scanner is already installed"
  else
    pass "S4b — an absent scanner is never announced as present"
  fi
fi

# ── S5 — THE PLACEMENT IS PINNED, NOT ASSERTED. The fast path sits BELOW the
# resolver-existence arm so a broken framework checkout keeps its diagnostic
# on a host that has the scanner. A cut of this fix had it above, lost the
# diagnostic, and shipped under a comment claiming behaviour-identity; the
# review found it by running main and the branch side by side. Moving the
# block back above the arm passed 51/0 — nothing here could see it. This case
# is the regression test: it fails on that ordering directly, so it needs no
# mutant of its own.
S5="$(newtmp)"
mkdir -p "$S5/fw" "$S5/p" "$S5/bin"
if ! mk_mirror "$S5/fw"; then
  fail_ "S5 setup" "could not mirror the framework"
elif ! _mk_gitleaks_shim "$S5/bin"; then
  fail_ "S5 setup" "the gitleaks shim did not resolve first on PATH"
elif ! mk_adoptee "$S5/p"; then
  fail_ "S5 setup" "could not build the adoptee"
else
  rm -f "$S5/fw/scripts/resolve-tools.sh"
  if [ -e "$S5/fw/scripts/resolve-tools.sh" ]; then
    fail_ "S5 setup" "could not remove the mirror's resolver"
  else
    _ans 1 > "$S5/answers"
    run_adopt "$S5/p" "$S5/answers" "$REPORT" "$S5/fw" "PATH=$S5/bin:$PATH"
    if grep -q "The tool resolver is not where it should be" "$RUN_OUT" 2>/dev/null; then
      pass "S5 — a missing resolver is still diagnosed when the scanner is present: the fast path sits below that arm"
    else
      fail_ "S5" "the fast path fired past a missing resolver — a broken checkout lost its only diagnostic"
    fi
    [ "$RUN_RC" -eq 0 ] \
      && pass "S5b — and the adoption still completes (rc=0)" \
      || fail_ "S5b" "adoption exited $RUN_RC on the missing-resolver arm"
  fi
fi

echo "=== MS — mutation proofs for the fast path ==="

# ── MS1 — remove the short-circuit and S1's non-execution assertion must die.
MS1_MARK="# BL-251-FAST-PATH"
MS1="$(newtmp)"
mkdir -p "$MS1/fw" "$MS1/p" "$MS1/bin"
if ! mk_mirror "$MS1/fw"; then
  fail_ "MS1 setup" "could not mirror the framework"
elif [ "$(_mutate "$MS1/fw" "adopt-tools.sh" "$MS1_MARK" "  if false; then   $MS1_MARK")" != "1" ]; then
  fail_ "MS1 setup" "the fast-path mutation did not apply cleanly"
elif ! _mk_gitleaks_shim "$MS1/bin"; then
  fail_ "MS1 setup" "the gitleaks shim did not resolve first on PATH"
elif ! _mk_sentinel_resolver "$MS1/fw/scripts/resolve-tools.sh" "$MS1/ran"; then
  fail_ "MS1 setup" "the sentinel resolver did not build"
elif ! mk_adoptee "$MS1/p"; then
  fail_ "MS1 setup" "could not build the adoptee"
else
  _ans 1 > "$MS1/answers"
  run_adopt "$MS1/p" "$MS1/answers" "$REPORT" "$MS1/fw" "PATH=$MS1/bin:$PATH"
  if [ -e "$MS1/ran" ]; then
    pass "MS1 (MUTATION) — without the short-circuit the resolver IS spawned: S1 is what stops it"
  else
    fail_ "MS1 (MUTATION)" "disabling the short-circuit changed nothing — S1 may be passing for another reason"
  fi
fi

# ── MS2 — remove the SEAM arm of the probe and S2 must die. This is the
# defect the review measured: without this line the host probe outranks
# SOIF_ADOPT_RESOLVER and nine assertions above turn host-dependent.
MS2_MARK="# BL-251-PROBE-SEAM"
MS2="$(newtmp)"
mkdir -p "$MS2/fw" "$MS2/p" "$MS2/bin"
if ! mk_mirror "$MS2/fw"; then
  fail_ "MS2 setup" "could not mirror the framework"
elif [ "$(_mutate "$MS2/fw" "adopt-tools.sh" "$MS2_MARK" "  :   $MS2_MARK")" != "1" ]; then
  fail_ "MS2 setup" "the probe-seam mutation did not apply cleanly"
elif ! _mk_gitleaks_shim "$MS2/bin"; then
  fail_ "MS2 setup" "the gitleaks shim did not resolve first on PATH"
elif ! _mk_sentinel_resolver "$MS2/resolver" "$MS2/ran"; then
  fail_ "MS2 setup" "the sentinel resolver did not build"
elif ! mk_adoptee "$MS2/p"; then
  fail_ "MS2 setup" "could not build the adoptee"
else
  _ans 1 > "$MS2/answers"
  run_adopt "$MS2/p" "$MS2/answers" "$REPORT" "$MS2/fw" \
    "SOIF_ADOPT_RESOLVER=$MS2/resolver" "PATH=$MS2/bin:$PATH"
  if [ -e "$MS2/ran" ]; then
    fail_ "MS2 (MUTATION)" "removing the seam arm changed nothing — S2 may be passing for another reason"
  else
    pass "MS2 (MUTATION) — without the seam arm the stub is bypassed: S2 is what keeps the suite host-independent"
  fi
fi

# ── MS4 — the fast path must not become a shortcut past the re-scan. S3 is a
# regression guard that passes on a tree with no fast path at all, so it needs
# a mutant of its own or it proves nothing.
MS4_MARK="# BL-251-FAST-PATH-RESCAN"
MS4="$(newtmp)"
mkdir -p "$MS4/fw" "$MS4/p" "$MS4/bin"
if ! mk_mirror "$MS4/fw"; then
  fail_ "MS4 setup" "could not mirror the framework"
elif [ "$(_mutate "$MS4/fw" "adopt-tools.sh" "$MS4_MARK" "    :   $MS4_MARK")" != "1" ]; then
  fail_ "MS4 setup" "the fast-path-rescan mutation did not apply cleanly"
elif ! _mk_gitleaks_shim "$MS4/bin"; then
  fail_ "MS4 setup" "the gitleaks shim did not resolve first on PATH"
elif ! _mk_sentinel_resolver "$MS4/fw/scripts/resolve-tools.sh" "$MS4/ran"; then
  fail_ "MS4 setup" "the sentinel resolver did not build"
elif ! mk_adoptee "$MS4/p"; then
  fail_ "MS4 setup" "could not build the adoptee"
else
  jq '.secrets.status = "tool-unavailable"' "$REPORT" > "$MS4/report.json" 2>/dev/null
  _ans 1 > "$MS4/answers"
  run_adopt "$MS4/p" "$MS4/answers" "$MS4/report.json" "$MS4/fw" "PATH=$MS4/bin:$PATH"
  if grep -q "The scan was re-run" "$RUN_OUT" 2>/dev/null; then
    fail_ "MS4 (MUTATION)" "dropping the re-scan changed nothing — S3 may be passing for another reason"
  else
    pass "MS4 (MUTATION) — without the re-scan call a degraded survey is left stale: S3 is what stops it"
  fi
fi

# ── MS5 — neuter the host probe and S4 must die. This is the mutant the first
# cut of this fix did not have: it survived the entire suite and every
# PR-blocking check, on the secret-scanner surface.
MS5_MARK="# BL-251-PROBE-HOST"
MS5="$(newtmp)"
mkdir -p "$MS5/fw" "$MS5/p" "$MS5/bin"
if ! mk_mirror "$MS5/fw"; then
  fail_ "MS5 setup" "could not mirror the framework"
elif [ "$(_mutate "$MS5/fw" "adopt-tools.sh" "$MS5_MARK" "  true   $MS5_MARK")" != "1" ]; then
  fail_ "MS5 setup" "the probe-host mutation did not apply cleanly"
elif ! _mk_gitleaks_shim "$MS5/bin"; then
  fail_ "MS5 setup" "the gitleaks shim did not resolve first on PATH"
elif ! _mk_sentinel_resolver "$MS5/fw/scripts/resolve-tools.sh" "$MS5/ran" auto; then
  fail_ "MS5 setup" "the sentinel resolver did not build"
elif ! mk_adoptee "$MS5/p"; then
  fail_ "MS5 setup" "could not build the adoptee"
else
  _ans_install 1 2 > "$MS5/answers"
  run_adopt "$MS5/p" "$MS5/answers" "$REPORT" "$MS5/fw" \
    "PATH=$MS5/bin:$PATH" "SOIF_ADOPT_SCANNER_BIN=gitleaks-bl251-absent"
  if [ -e "$MS5/ran" ]; then
    fail_ "MS5 (MUTATION)" "neutering the host probe changed nothing — S4 may be passing for another reason"
  else
    pass "MS5 (MUTATION) — with the probe forced true an absent scanner is announced as present: S4 is what stops it"
  fi
fi

# ── MS3 — the four SINGLE-SITE markers are unique and end-of-line anchored, so the
# mutations above cannot silently hit a second site.
for _m in "$MS1_MARK" "$MS2_MARK" "$MS4_MARK" "$MS5_MARK"; do
  _n="$(_sites "$L_TOOLS" "$_m")"
  [ "$_n" = "1" ] \
    && pass "MS3 — '$_m' occurs exactly once at end-of-line in adopt-tools.sh" \
    || fail_ "MS3" "'$_m' occurs $_n times in adopt-tools.sh (need exactly 1)"
done

# ── MS7 — THE PROBE'S DEFAULT IS THE MATRIX'S OWN SCANNER NAME, derived rather
# than transcribed. Every absence case sets SOIF_ADOPT_SCANNER_BIN explicitly
# and every presence case is satisfied by whatever binary happens to exist, so
# the literal default was asserted by NOTHING: changing it to `git` (always
# present) survived the whole suite while a gitleaks-free host was told the
# scanner was already installed. A typo or a rename would fail SAFE (the probe
# stops matching and the resolver runs) — only a nonsense substitution is
# dangerous — which is why this is a name-tie rather than a mutant: it also
# pins the one hardcoded `gitleaks` in this file that has no category
# fallback to the entry the resolver actually keys off.
_mx="$(jq -r '[.tools[]|select(.substitution_category=="Secret Detection")|.name]|first // ""' "$REPO_ROOT/templates/tool-matrix/common.json" 2>/dev/null)"
if [ -z "$_mx" ]; then
  fail_ "MS7 setup" "could not derive the Secret Detection tool name from templates/tool-matrix/common.json"
elif grep -q "SOIF_ADOPT_SCANNER_BIN:-${_mx}}\"   # BL-251-PROBE-HOST\$" "$L_TOOLS" 2>/dev/null; then
  pass "MS7 — the probe's default is the matrix's own scanner name ($_mx)"
else
  fail_ "MS7" "the fast path probes for a different tool than the matrix resolves (matrix says '$_mx')"
fi

# ── MS6 — `# BL-251-ALREADY-LINE` is a SYNC-SIBLING marker, so its invariant is
# TWO sites, not one: the fast path and the resolver's already-installed arm
# print byte-identical text, and this repo's convention for text duplicated in
# lockstep is a grep-able marker (`# BL-084-TIER-KEY`, "SYNC SIBLINGS") rather
# than a prose pointer. If one line moves without the other the count changes.
_al_sites="$(_sites "$L_TOOLS" "# BL-251-ALREADY-LINE")"
[ "$_al_sites" = "2" ] \
  && pass "MS6 — '# BL-251-ALREADY-LINE' marks both sync siblings (2 sites)" \
  || fail_ "MS6" "'# BL-251-ALREADY-LINE' occurs $_al_sites times in adopt-tools.sh (need exactly 2)"

_al_text="$(grep -c '^ *adopt_note "Secret detection: already installed\. The history scan can run\."   # BL-251-ALREADY-LINE$' "$L_TOOLS" 2>/dev/null)"
[ "$(_num "$_al_text")" = "2" ] \
  && pass "MS6b — both sync siblings still carry byte-identical operator text" \
  || fail_ "MS6b" "the two '# BL-251-ALREADY-LINE' sites have drifted apart"

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "Results: $PASSED passed, $FAILED failed"
  exit 0
fi
echo "Results: $PASSED passed, $FAILED failed"
exit 1
