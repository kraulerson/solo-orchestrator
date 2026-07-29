#!/usr/bin/env bash
# tests/test-bl118-sast-dom-xss.sh — BL-118: the SAST gate must SEE browser DOM XSS.
#
# WHY THIS EXISTS (Dogfood-2 finding F-DF2-007, Critical)
#   BL-112 armed the pre-commit SAST gate (--error is passed, the [BLOCKED] arm
#   is reachable, the verdict propagates) — but aimed it at `p/owasp-top-ten`,
#   a ruleset that contains NO browser DOM-sink rules. A real stored DOM XSS
#   (`pane.innerHTML = <attacker-influenced markup>`) was staged on the flagship
#   web/typescript platform; the hook printed
#   `[OK] semgrep: SAST ran on N staged file(s) — no ERROR-severity findings`
#   and the vulnerability reached main. CI shares the blindness (the generated
#   pipelines run `p/owasp-top-ten, p/security-audit`). The gun was loaded by
#   BL-112; it was never pointed at the #1 web vulnerability class.
#
#   The fix adds `r/javascript.browser.security.insecure-document-method`
#   (registry severity=ERROR, so it survives the --severity=ERROR bound) to
#   every emitter of the SAST invocation:
#     • scripts/lib/hook-templates.sh   (# BL-118-DOMXSS-CONFIG) — the single
#       source of truth for the generated .git/hooks/pre-commit
#     • templates/pipelines/ci/{github,gitlab}/*.yml — the generated CI
#     • scripts/verify-install.sh fix_precommit_hook (# BL-118-SINGLE-SOURCE) —
#       which used to REWRITE the hook from an inline pre-BL-099/BL-112 heredoc
#       (blind ruleset, --quiet, no --error => dead [BLOCKED] arm, no managed-
#       region markers), i.e. the repair tool re-installed the exact defects
#       BL-112/BL-118 fixed. It must delegate to the lib, never inline a body.
#
# CASES
#   T-hook-carries-domxss-config     hermetic — the lib-emitted hook's semgrep
#                                    invocation carries the DOM-sink config AND
#                                    still carries p/owasp-top-ten, --severity=ERROR
#                                    and --error (the fix must ADD coverage, not
#                                    trade away BL-112's).
#   T-predicate-no-sigpipe           hermetic — has_live/has_cfg must survive a
#                                    file with megabytes of content AFTER the
#                                    match. The pipe spelling they replaced
#                                    (# BL-183-NO-SIGPIPE) returns 141 there and
#                                    reports a PRESENT string as ABSENT, which is
#                                    how a green macOS run shipped a CI failure
#                                    claiming `p/owasp-top-ten dropped`. This case
#                                    guards the predicates themselves — without it
#                                    every other case here is only as trustworthy
#                                    as the helper it calls.
#   T-ci-templates-carry-domxss-config hermetic — all generated CI pipelines
#                                    (github + gitlab, every language) carry the
#                                    DOM-sink config on their semgrep step.
#   T-verify-install-fix-single-source hermetic — fix_precommit_hook, run inside
#                                    a bare project (no framework source), writes
#                                    a hook that carries the managed-region marker
#                                    and the DOM-sink config: proof it delegates
#                                    to the lib instead of inlining a stale body.
#   T-domxss-blocks-real-commit      live — a REAL `git commit` of
#                                    `pane.innerHTML = userText` through the
#                                    lib-emitted hook is REFUSED BY GIT with
#                                    [BLOCKED] and HEAD unmoved.
#                                    (LOUD SKIP if semgrep absent / registry down.)
#   T-domxss-clean-still-commits     live — the textContent fix commits clean AND
#                                    the [OK] receipt proves the scan RAN (without
#                                    that, this case passes vacuously on a host
#                                    where nothing scanned). (LOUD SKIP as above.)
#   T-mutation-domxss-config         live — strip the DOM-sink config line from
#                                    the emitted hook -> the SAME XSS commit LANDS:
#                                    the added config is load-bearing, not
#                                    decorative. Fails if there is no config line
#                                    to strip. (LOUD SKIP as above.)
#
# REGISTRATION: never runs init.sh, not an aggregator -> registered in BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit fast lane (where the
# live cases skip loudly — the hermetic config pins still run and still bite).
#
# Hermetic: mktemp workdirs, local git identity, GITHUB_BASE_REF unset, no
# remote ever contacted. The live cases talk to the semgrep registry (config
# fetch) — a host where that fails yields LOUD SKIPs, never silent passes.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# The DOM-sink ruleset the fix adds. Registry rule pack; both of its rules
# (innerHTML/outerHTML assignment, document.write/writeln) are severity=ERROR,
# verified 2026-07-17 against semgrep 1.157.0 --json output.
DOMXSS_CFG='r/javascript.browser.security.insecure-document-method'

# Comment-stripped fixed-string search: a config that only survives in a comment
# is not a config. Returns 0 iff the string appears on a non-comment line.
#
# BL-183-NO-SIGPIPE — ONE PROCESS, NO PIPE, AND THAT IS THE WHOLE POINT. This was
# `grep -v '^[[:space:]]*#' "$1" | grep -qF -- "$2"`, and under this file's
# `set -uo pipefail` that spelling INVERTS ITS OWN VERDICT: `grep -q` exits the
# instant it matches, closing the read end, so the still-writing `grep -v` takes
# EPIPE/SIGPIPE, and pipefail hands the pipeline that failure — a FOUND result
# reported as NOT FOUND. It is a race on how much the producer has left to write,
# so it hides while a file is small and surfaces when it grows. That is exactly
# what happened: the emitted hook went 645 -> 1231 lines and CI went red on
# GitHub's Linux runner with `grep: write error: Broken pipe` in the log, while
# every local macOS run stayed green. The failure was maximally misleading — it
# claimed `p/owasp-top-ten dropped`, a security regression, when the config was
# present the whole time. awk with index() gives the same fixed-string,
# comment-stripped semantics in a single process, so there is no pipe to break.
#
# FALSIFIER — restore the pipe spelling and run, from a bash shell:
#   printf 'MATCH_ME\n' > /tmp/e.txt; for i in $(seq 1 200000); do echo "f $i"; done >> /tmp/e.txt
#   bash -c 'set -uo pipefail; grep -v "^[[:space:]]*#" /tmp/e.txt | grep -qF -- MATCH_ME
#            echo "rc=$? PIPESTATUS=${PIPESTATUS[*]}"'
# Measured on this host: `rc=141 PIPESTATUS=141 0` — the match is on line 1 and
# the predicate still reports failure. The awk form below returns rc=0. The
# ~3 MB of trailing filler is the PRECONDITION: it makes the race deterministic.
# Without it the producer usually finishes first and the bug stays invisible.
has_live() { # <file> <fixed-string>
  # The needle travels via the environment, not `awk -v`: -v processes backslash
  # escapes in the value, which would silently corrupt any needle containing one.
  SOIF_NEEDLE="$2" awk '
    /^[[:space:]]*#/ { next }
    index($0, ENVIRON["SOIF_NEEDLE"]) { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

# EXACT-TOKEN pin for the DOM-sink config (adversarial-verifier finding,
# 2026-07-17): a suffix-typo'd rule path (…-methodTYPO) combined with a valid
# pack resolves SILENTLY EMPTY — semgrep exits 0 with a green banner and zero
# warnings — so a substring grep would bless a hook whose scan lost its rules.
# Require a boundary before (`=` or whitespace) and after (whitespace, a line
# continuation `\`, a flow-sequence `]`, or end-of-line) the rule id.
DOMXSS_CFG_RE='(=|[[:space:]])r/javascript\.browser\.security\.insecure-document-method([[:space:]]|\\|]|$)'
has_cfg() { # <file>
  # BL-183-NO-SIGPIPE — same inversion, same fix as has_live above; see its
  # comment for the mechanism and the runnable falsifier. `$0 ~ str` is awk's
  # dynamic-regex form and takes the SAME ERE dialect grep -E was given, so
  # DOMXSS_CFG_RE is reused verbatim rather than re-spelled for a second engine.
  SOIF_RE="$DOMXSS_CFG_RE" awk '
    /^[[:space:]]*#/ { next }
    $0 ~ ENVIRON["SOIF_RE"] { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

# ── T-predicate-no-sigpipe ───────────────────────────────────────────────────
# Guards the two helpers above. Runs FIRST: if the predicates lie, every verdict
# below is worthless, so this must be the first thing that goes red.
echo "=== T-predicate-no-sigpipe ==="
SIGP_FX="$TOPTMP/sigpipe-fixture.txt"
{
  echo '  --config=r/javascript.browser.security.insecure-document-method \'
  echo '  --config=p/owasp-top-ten \'
  # ~3 MB of trailing content is the PRECONDITION, not padding: it is what makes
  # the producer still be writing when the consumer exits. Shrink it and the old
  # spelling passes here while still failing on a real hook — a guard that cannot
  # fail is worse than no guard.
  awk 'BEGIN { for (i = 0; i < 200000; i++) print "filler line " i }'
} > "$SIGP_FX"
sigp_bytes=$(wc -c < "$SIGP_FX" | tr -d ' ')
if [ "$sigp_bytes" -lt 1000000 ]; then
  fail_ "T-predicate-no-sigpipe" "fixture is only $sigp_bytes bytes — too small to force the race; this case would pass vacuously"
elif ! has_live "$SIGP_FX" "p/owasp-top-ten"; then
  fail_ "T-predicate-no-sigpipe" "has_live reported an ABSENT string that is on line 2 of a ${sigp_bytes}-byte file — the predicate is pipe-based again and inverts under set -o pipefail (BL-183)"
elif ! has_cfg "$SIGP_FX"; then
  fail_ "T-predicate-no-sigpipe" "has_cfg reported an ABSENT config that is on line 1 of a ${sigp_bytes}-byte file — same inversion (BL-183)"
elif has_live "$SIGP_FX" "p/definitely-not-in-this-file"; then
  fail_ "T-predicate-no-sigpipe" "has_live reported a string that is NOT in the fixture — the predicate now passes vacuously, which would bless any hook"
else
  pass "T-predicate-no-sigpipe (both predicates correct across ${sigp_bytes} bytes, in both directions)"
fi

# ── T-hook-carries-domxss-config ─────────────────────────────────────────────
echo "=== T-hook-carries-domxss-config ==="
HOOK_SRC="$REPO_ROOT/scripts/lib/hook-templates.sh"
EMITTED="$TOPTMP/emitted-hook"
if [ ! -f "$HOOK_SRC" ]; then
  fail_ "T-hook-carries-domxss-config" "scripts/lib/hook-templates.sh missing"
else
  # shellcheck source=/dev/null
  . "$HOOK_SRC"
  soif_write_precommit_hook "$EMITTED"
  if [ ! -x "$EMITTED" ]; then
    fail_ "T-hook-carries-domxss-config" "soif_write_precommit_hook produced no executable hook"
  elif ! has_cfg "$EMITTED"; then
    fail_ "T-hook-carries-domxss-config" "emitted hook's semgrep invocation lacks $DOMXSS_CFG as an exact token (BL-118: the gate cannot see innerHTML — or the rule id is typo'd, which resolves silently empty)"
  elif ! has_live "$EMITTED" "p/owasp-top-ten"; then
    fail_ "T-hook-carries-domxss-config" "p/owasp-top-ten dropped — the fix must ADD DOM coverage, not trade away the Express-RCE coverage BL-112 proved"
  elif ! has_live "$EMITTED" "--severity=ERROR" || ! has_live "$EMITTED" "--error"; then
    fail_ "T-hook-carries-domxss-config" "--severity=ERROR/--error weakened (BL-112 regression)"
  else
    pass "T-hook-carries-domxss-config"
  fi
fi

# ── T-ci-templates-carry-domxss-config ───────────────────────────────────────
echo "=== T-ci-templates-carry-domxss-config ==="
missing=""
count=0
for tpl in "$REPO_ROOT"/templates/pipelines/ci/github/*.yml "$REPO_ROOT"/templates/pipelines/ci/gitlab/*.yml; do
  [ -f "$tpl" ] || continue
  count=$((count + 1))
  if ! has_cfg "$tpl"; then
    missing="$missing ${tpl#"$REPO_ROOT"/}"
  fi
done
if [ "$count" -eq 0 ]; then
  fail_ "T-ci-templates-carry-domxss-config" "no CI templates found under templates/pipelines/ci/ — wrong path?"
elif [ -n "$missing" ]; then
  fail_ "T-ci-templates-carry-domxss-config" "$(echo "$missing" | wc -w | tr -d ' ') of $count CI templates lack $DOMXSS_CFG:$missing"
else
  pass "T-ci-templates-carry-domxss-config ($count templates)"
fi

# ── T-verify-install-fix-single-source ───────────────────────────────────────
# Extract fix_precommit_hook from verify-install.sh and run it inside a bare
# project that has ONLY the project-local scripts/lib/hook-templates.sh (no
# framework source available): the hook it repairs must be the lib-emitted one.
echo "=== T-verify-install-fix-single-source ==="
VI="$REPO_ROOT/scripts/verify-install.sh"
EXTRACT="$TOPTMP/fix_precommit_hook.sh"
awk '/^fix_precommit_hook\(\) \{/,/^\}/' "$VI" > "$EXTRACT"
if ! grep -q 'fix_precommit_hook' "$EXTRACT"; then
  fail_ "T-verify-install-fix-single-source" "could not extract fix_precommit_hook() from verify-install.sh (function renamed/moved?)"
else
  PROJ="$TOPTMP/vi-proj"
  mkdir -p "$PROJ/scripts/lib"
  cp "$HOOK_SRC" "$PROJ/scripts/lib/hook-templates.sh"
  ( cd "$PROJ" && git init -q )
  DRIVER="$TOPTMP/vi-driver.sh"
  {
    echo 'set -uo pipefail'
    # No framework source on this host: the repair must work from the
    # project-local lib alone (has_source stubbed false, like a moved checkout).
    echo 'has_source() { return 1; }'
    echo 'SOURCE_DIR=""'
    echo ". '$EXTRACT'"
    echo 'fix_precommit_hook'
  } > "$DRIVER"
  if ! ( cd "$PROJ" && bash "$DRIVER" ) >"$TOPTMP/vi-out" 2>&1; then
    fail_ "T-verify-install-fix-single-source" "fix_precommit_hook errored: $(tail -2 "$TOPTMP/vi-out" | tr '\n' ' ')"
  elif [ ! -x "$PROJ/.git/hooks/pre-commit" ]; then
    fail_ "T-verify-install-fix-single-source" "no executable .git/hooks/pre-commit written"
  elif ! grep -qF '# >>> SOIF pre-commit fallback' "$PROJ/.git/hooks/pre-commit"; then
    fail_ "T-verify-install-fix-single-source" "repaired hook lacks the managed-region marker — it was inlined from a heredoc, not emitted by the lib (stale-emitter drift: the repair path re-installs pre-BL-099/BL-112 bytes)"
  elif ! has_cfg "$PROJ/.git/hooks/pre-commit"; then
    fail_ "T-verify-install-fix-single-source" "repaired hook lacks $DOMXSS_CFG as an exact token — repair re-blinds the SAST gate"
  else
    pass "T-verify-install-fix-single-source"
  fi
fi

# ── Live cases: a REAL git commit through the emitted hook ───────────────────
HAVE_SEMGREP=0
if command -v semgrep >/dev/null 2>&1; then
  HAVE_SEMGREP=1
else
  echo ""
  echo "#################################################################"
  echo "## semgrep IS NOT INSTALLED ON THIS HOST.                      ##"
  echo "## The three live cases are SKIPPED, NOT PASSED:               ##"
  echo "##   T-domxss-blocks-real-commit                               ##"
  echo "##   T-domxss-clean-still-commits                              ##"
  echo "##   T-mutation-domxss-config                                  ##"
  echo "## The DOM-XSS *blocking* behaviour is UNPROVEN here. The      ##"
  echo "## config pins above still bind every emitter to the ruleset.  ##"
  echo "## Install semgrep to exercise them: brew install semgrep      ##"
  echo "#################################################################"
  echo ""
fi

# mk_live_repo <dir>: fresh repo, local identity, one benign commit landed
# BEFORE the hook is installed (so HEAD exists and the initial commit does not
# pay a semgrep run), then the lib-emitted hook installed as pre-commit.
mk_live_repo() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl118@test.invalid" \
      && git config user.name  "BL-118 Test" \
      && echo "# bl118" > README.md \
      && git add README.md \
      && git commit -q -m "chore: init" ) || return 1
  # BL-131/BL-132: the emitted hook now --config's .semgrep/soif-dom-sinks.yml
  # (repo-relative) and scans a materialized index tree. Ship the ruleset so the
  # SAST arm actually RUNS here instead of NOTRUN-ing on a missing config — bl118's
  # own fixtures are innerHTML (registry-covered), so this is wiring, not coverage,
  # but without it every live case below would LOUD-SKIP.
  if [ -f "$REPO_ROOT/templates/semgrep/soif-dom-sinks.yml" ]; then
    mkdir -p "$d/.semgrep"
    cp "$REPO_ROOT/templates/semgrep/soif-dom-sinks.yml" "$d/.semgrep/soif-dom-sinks.yml"
  fi
  cp "$EMITTED" "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
}

XSS_TS='export function render(pane: HTMLElement, userText: string) {
  pane.innerHTML = userText;
}'
SAFE_TS='export function render(pane: HTMLElement, userText: string) {
  pane.textContent = userText;
}'

# commit_file <repo> <name> <content> <outfile>; echoes nothing, returns git's rc.
commit_file() {
  local d="$1" name="$2" content="$3" out="$4"
  printf '%s\n' "$content" > "$d/$name"
  ( cd "$d" && git add "$name" && git commit -m "feat: $name" ) >"$out" 2>&1
}

# not_enforced <outfile>: the hook's own NOTRUN receipt — scanner did not run
# (absent/registry down). That outcome proves nothing either way -> LOUD SKIP.
not_enforced() { grep -q "SAST NOT ENFORCED" "$1"; }

if [ "$HAVE_SEMGREP" -eq 1 ]; then
  # ── T-domxss-blocks-real-commit ────────────────────────────────────────────
  echo "=== T-domxss-blocks-real-commit ==="
  R1="$TOPTMP/live-block"
  if ! mk_live_repo "$R1"; then
    fail_ "T-domxss-blocks-real-commit" "live repo setup failed"
  else
    head_before="$(cd "$R1" && git rev-parse HEAD)"
    commit_file "$R1" "app.ts" "$XSS_TS" "$TOPTMP/out1"
    rc=$?
    head_after="$(cd "$R1" && git rev-parse HEAD)"
    if [ "$rc" -eq 0 ]; then
      if not_enforced "$TOPTMP/out1"; then
        skip_ "T-domxss-blocks-real-commit" "scanner did not run (registry unreachable?) — blocking behaviour UNPROVEN on this host"
      else
        fail_ "T-domxss-blocks-real-commit" "pane.innerHTML = userText COMMITTED CLEAN through the hook (BL-118: ruleset blind to DOM XSS; output: $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/out1" | head -1))"
      fi
    elif ! grep -q "\[BLOCKED\]" "$TOPTMP/out1"; then
      fail_ "T-domxss-blocks-real-commit" "commit refused but without the [BLOCKED] verdict (rc=$rc) — wrong reason"
    elif [ "$head_before" != "$head_after" ]; then
      fail_ "T-domxss-blocks-real-commit" "hook exited non-zero but HEAD MOVED"
    else
      pass "T-domxss-blocks-real-commit"
    fi
  fi

  # ── T-domxss-clean-still-commits ───────────────────────────────────────────
  echo "=== T-domxss-clean-still-commits ==="
  R2="$TOPTMP/live-clean"
  if ! mk_live_repo "$R2"; then
    fail_ "T-domxss-clean-still-commits" "live repo setup failed"
  else
    commit_file "$R2" "safe.ts" "$SAFE_TS" "$TOPTMP/out2"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      fail_ "T-domxss-clean-still-commits" "the textContent FIX was blocked (false positive; rc=$rc): $(grep '\[BLOCKED\]' "$TOPTMP/out2" | head -1)"
    elif not_enforced "$TOPTMP/out2"; then
      skip_ "T-domxss-clean-still-commits" "scanner did not run — clean-commit case is vacuous on this host"
    elif ! grep -q "\[OK\] semgrep: SAST ran" "$TOPTMP/out2"; then
      fail_ "T-domxss-clean-still-commits" "commit landed but WITHOUT the [OK] scan receipt — cannot distinguish 'scanned clean' from 'never scanned'"
    else
      pass "T-domxss-clean-still-commits"
    fi
  fi

  # ── T-mutation-domxss-config ───────────────────────────────────────────────
  # The in-test mutation: strip the DOM-sink config from the hook -> the same
  # XSS must COMMIT CLEAN. Proves the added config (and nothing else) is what
  # stands between an innerHTML sink and main.
  echo "=== T-mutation-domxss-config ==="
  R3="$TOPTMP/live-mut"
  if ! mk_live_repo "$R3"; then
    fail_ "T-mutation-domxss-config" "live repo setup failed"
  elif ! has_cfg "$R3/.git/hooks/pre-commit"; then
    fail_ "T-mutation-domxss-config" "no $DOMXSS_CFG token in the emitted hook to strip — the fix is not in place"
  else
    sed "/insecure-document-method/d" "$R3/.git/hooks/pre-commit" > "$R3/.git/hooks/pre-commit.mut" \
      && mv "$R3/.git/hooks/pre-commit.mut" "$R3/.git/hooks/pre-commit" \
      && chmod +x "$R3/.git/hooks/pre-commit"
    if ! bash -n "$R3/.git/hooks/pre-commit" 2>/dev/null; then
      fail_ "T-mutation-domxss-config" "stripping the config line broke the hook's syntax — keep the config on its own continuation line"
    else
      commit_file "$R3" "app.ts" "$XSS_TS" "$TOPTMP/out3"
      rc=$?
      if [ "$rc" -ne 0 ]; then
        fail_ "T-mutation-domxss-config" "XSS still blocked WITHOUT the DOM-sink config (rc=$rc) — then what is doing the blocking? The config pin is not proving what it claims"
      elif not_enforced "$TOPTMP/out3"; then
        skip_ "T-mutation-domxss-config" "scanner did not run — mutation direction unprovable on this host"
      else
        pass "T-mutation-domxss-config"
      fi
    fi
  fi
else
  skip_ "T-domxss-blocks-real-commit"  "semgrep absent"
  skip_ "T-domxss-clean-still-commits" "semgrep absent"
  skip_ "T-mutation-domxss-config"     "semgrep absent"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed ($SKIPPED skipped)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
