#!/usr/bin/env bash
# tests/test-bl180-interactive-scaffold-pty.sh — BL-180 end-to-end proof.
#
# WHAT THIS PROVES THAT NOTHING ELSE DOES
#   A REAL interactive scaffold — init.sh with NO flags, driven over a pty so
#   helpers-core.sh::prompt_input takes its interactive branch — produces a
#   project whose manifest carries enforcement_level="strict" AND whose
#   .git/hooks/ actually contains the strict-mode filesystem gate. Pre-BL-180
#   that combination was impossible: main()'s `# BL-030: resolve
#   enforcement_level` block sits inside the NON_INTERACTIVE arm, so the
#   interactive arm reached prepare_initial_state_for_commit with
#   ENFORCEMENT_LEVEL="" — the manifest recorded "" and the
#   `[ "$ENFORCEMENT_LEVEL" = "strict" ]` guard around
#   install-filesystem-gates.sh --install silently did nothing. The fix is the
#   `# BL-180-ENFORCEMENT-DEFAULT` line in init.sh::main.
#
#   Every OTHER init.sh fixture in tests/ is either --non-interactive (which
#   resolves the level on a different code path) or --dry-run (which returns
#   from main() before create_project and never writes a manifest). That is
#   precisely why this defect shipped, so the pin has to be a real scaffold.
#
# WHY AGGREGATOR-ONLY
#   This performs a full create_project (framework clone, template render, git
#   init + commit, verify-install) over a pty. It is minutes, not seconds, and
#   it invokes init.sh — so it is registered in tests/full-project-test-suite.sh
#   ONLY and must NOT be added to the .github/workflows/tests.yml unit lane.
#   The fast pin for the same defect is tests/test-bl180-interactive-enforcement.sh.
#
# FIXTURE-SCOPED — and this is NOT free (see # BL-180-PTY-INTERACTIVE-ENV):
#   prompt_input's non-interactive guard fires on CI / SOIF_NONINTERACTIVE
#   INDEPENDENTLY of the tty, and when it does this run scaffolds into the
#   checkout's PARENT rather than into its own mktemp -d. Those two vars are
#   therefore unset for the run, T0a refuses to spawn init.sh if that unset
#   ever stops taking, and T0b fails loudly if anything lands outside anyway.
#
# HERMETIC — no remote is ever contacted:
#   * Git host is answered "other", the URL-paste path. It never invokes gh /
#     glab / curl, so no authenticated host account can be touched.
#   * The clone-URL prompt is answered with an EMPTY line, so
#     create_and_protect_remote fails at its `[ -z "$remote_url" ]` guard
#     BEFORE `git remote add origin` — nothing is even resolved, let alone
#     pushed. init.sh consequently returns 2 via record_init_failure. That
#     non-zero rc is EXPECTED and is deliberately NOT asserted: pinning it
#     would couple this test to unrelated host-setup outcomes. It is printed
#     in the T0 line for diagnosis, and the real guarantees are carried by
#     T1 (the scaffold happened) and T7 (no remote was ever attached).
#   * A mock gh/glab is prepended to PATH as defence in depth (write_mock_gh).
#   * The assertions target artifacts written by prepare_initial_state_for_commit,
#     which runs BEFORE create_and_protect_remote — so the remote failure
#     cannot mask the thing under test.
#
# LOUD SKIP: when neither `expect` nor `script` is available this prints an
# explicit SKIPPED line with the reason and exits 0. It never silently passes
# assertions it did not run.
#
# DEV KNOB: SOIF_BL180_FORCE_SCRIPT_FALLBACK=1 forces the script(1) driver even
# when expect is present, so the fallback path stays exercised and honest.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Menu-ordinal derivation (mirrors init.sh::collect_project_info) ─────
# Hardcoded ordinals go stale whenever a platform module or CI template is
# added/removed — the failure mode that broke the aggregator's TEST 7 fixture
# before BL-136. Derive them, then bind the run to the combo they resolved to.
derive_platform_index() {
  local want="$1" idx=0 seen="" f p
  for f in "$REPO_ROOT/docs/platform-modules/"*.md; do
    [ -f "$f" ] || continue
    p="$(basename "$f" .md)"
    case " $seen " in *" $p "*) continue ;; esac
    seen="$seen $p"; idx=$((idx + 1))
    [ "$p" = "$want" ] && { echo "$idx"; return 0; }
  done
  for f in "$REPO_ROOT/templates/pipelines/release/github/"*.yml; do
    [ -f "$f" ] || continue
    p="$(basename "$f" .yml)"
    case " $seen " in *" $p "*) continue ;; esac
    seen="$seen $p"; idx=$((idx + 1))
    [ "$p" = "$want" ] && { echo "$idx"; return 0; }
  done
  idx=$((idx + 1))
  [ "$want" = "other" ] && { echo "$idx"; return 0; }
  return 1
}
derive_language_index() {
  local want="$1" platform="$2" idx=0 f l marker csv
  for f in "$REPO_ROOT/templates/pipelines/ci/github/"*.yml; do
    [ -f "$f" ] || continue
    l="$(basename "$f" .yml)"
    [ "$l" = "other" ] && continue
    marker="$(head -1 "$f")"
    csv=""
    case "$marker" in *"# solo-orchestrator: platforms="*) csv="${marker#*platforms=}" ;; esac
    if [ -z "$csv" ]; then
      idx=$((idx + 1))
    else
      case ",$csv," in
        *",$platform,"*) idx=$((idx + 1)) ;;
        *) continue ;;
      esac
    fi
    [ "$l" = "$want" ] && { echo "$idx"; return 0; }
  done
  idx=$((idx + 1))
  [ "$want" = "other" ] && { echo "$idx"; return 0; }
  return 1
}

# ── pty driver selection (LOUD SKIP when neither tool exists) ───────────
DRIVER=""
if [ "${SOIF_BL180_FORCE_SCRIPT_FALLBACK:-0}" = "1" ] && command -v script >/dev/null 2>&1; then
  DRIVER="script"
elif command -v expect >/dev/null 2>&1; then
  DRIVER="expect"
elif command -v script >/dev/null 2>&1; then
  DRIVER="script"
fi

if [ -z "$DRIVER" ]; then
  echo "  [SKIPPED] tests/test-bl180-interactive-scaffold-pty.sh — no pty driver available."
  echo "            Neither 'expect' nor 'script' is on PATH, so a REAL interactive"
  echo "            init.sh run (which requires a tty for helpers-core.sh::prompt_input)"
  echo "            cannot be driven. Install expect (brew install expect / apt-get"
  echo "            install -y expect) to run this test. The fast, pty-free pin for the"
  echo "            same defect is tests/test-bl180-interactive-enforcement.sh."
  echo ""
  echo "Results: 0 passed, 0 failed (SKIPPED: no pty driver)"
  exit 0
fi

PLATFORM_IDX="$(derive_platform_index web)" || PLATFORM_IDX=""
LANGUAGE_IDX="$(derive_language_index typescript web)" || LANGUAGE_IDX=""
if [ -z "$PLATFORM_IDX" ] || [ -z "$LANGUAGE_IDX" ]; then
  echo "  [FAIL] menu-ordinal derivation — platform='$PLATFORM_IDX' language='$LANGUAGE_IDX'"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

PROJ="$TMP/bl180pty"
TRANSCRIPT="$TMP/transcript.log"

# Hermetic git identity — a fixture must never depend on the host's global
# git config, and env vars beat config on every git version we support.
export GIT_AUTHOR_NAME="BL180 Fixture"
export GIT_AUTHOR_EMAIL="bl180@example.invalid"
export GIT_COMMITTER_NAME="BL180 Fixture"
export GIT_COMMITTER_EMAIL="bl180@example.invalid"
# Never let git open a credential prompt on the pty (would hang the driver).
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/usr/bin/true
# House rule: unset GITHUB_BASE_REF in fixture git ops.
unset GITHUB_BASE_REF 2>/dev/null || true

# ── BL-180-PTY-INTERACTIVE-ENV: neutralise the non-interactive overrides ─
# helpers-core.sh::prompt_input / prompt_yes_no / prompt_choice all guard on
#   [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]
# A pty satisfies `-t 0`, but CI and SOIF_NONINTERACTIVE are checked
# INDEPENDENTLY of the tty — so on any host that exports them (every GitHub
# Actions runner exports CI=true, which is precisely the environment of the
# `full` lane this test is registered into) prompt_input auto-returns its
# DEFAULT without consuming the fed answer. That is not merely a failing test:
# PROJECT_NAME resolves to "" and
#   PROJECT_DIR=$(prompt_input "Project directory" "$default_parent/$PROJECT_NAME")
# resolves to "$default_parent/" — the PARENT DIRECTORY OF THE CHECKOUT — so a
# complete git-init'd project is scaffolded OUTSIDE this fixture's own
# `mktemp -d`. Driving the INTERACTIVE branch is the entire point of this test,
# so these two are unset for the run. The piped/non-interactive branch is the
# fast pin's job (tests/test-bl180-interactive-enforcement.sh), not this one.
# T0a below re-asserts the unset actually took, and refuses to spawn init.sh
# if it did not.
unset CI 2>/dev/null || true
unset SOIF_NONINTERACTIVE 2>/dev/null || true

# Defence in depth: even though the "other" host path never shells out to a
# host CLI, make gh/glab resolve to refusing stubs for the whole run.
MOCK_DIR="$TMP/mockbin"
mkdir -p "$MOCK_DIR"
write_mock_gh() {
  cat > "$MOCK_DIR/gh" <<'MOCKEOF'
#!/usr/bin/env bash
echo "mock gh: refusing (hermetic fixture — no live remote)" >&2
exit 1
MOCKEOF
  chmod +x "$MOCK_DIR/gh"
}
write_mock_glab() {
  cat > "$MOCK_DIR/glab" <<'MOCKEOF'
#!/usr/bin/env bash
echo "mock glab: refusing (hermetic fixture — no live remote)" >&2
exit 1
MOCKEOF
  chmod +x "$MOCK_DIR/glab"
}
write_mock_gh
write_mock_glab
export PATH="$MOCK_DIR:$PATH"

# init.sh refuses to scaffold from inside the framework repo.
cd /tmp || exit 1

# ── T0a: PRE-FLIGHT CONTAINMENT — checked BEFORE init.sh is ever spawned ─
# This is the only assertion that can PREVENT rather than merely report an
# escape, so it is deliberately ordered ahead of the run and exits without
# spawning when it trips.
#
# ESCAPE_DIR is init.sh::collect_project_info's own expression
#   default_parent="$(cd "$SCRIPT_DIR/.." && pwd)"
# evaluated here with SCRIPT_DIR=$REPO_ROOT. When prompt_input takes its
# non-interactive branch, PROJECT_NAME="" and the run scaffolds a whole
# project into exactly this directory. Naming it up front is what makes a
# future escape legible instead of surfacing as a confusing "no manifest at
# <fixture path>" from T1.
ESCAPE_DIR="$(cd "$REPO_ROOT/.." 2>/dev/null && pwd)"

echo "T0a: pre-flight containment (interactive branch reachable, fixture-scoped)"
preflight_err=""
[ -n "${CI:-}" ] && preflight_err="CI is set ('$CI')"
[ -z "$preflight_err" ] && [ -n "${SOIF_NONINTERACTIVE:-}" ] \
  && preflight_err="SOIF_NONINTERACTIVE is set ('$SOIF_NONINTERACTIVE')"
if [ -z "$preflight_err" ]; then
  case "$PROJ/" in
    "$TMP"/*) : ;;
    *) preflight_err="PROJ ('$PROJ') is not under the fixture TMP ('$TMP')" ;;
  esac
fi
if [ -n "$preflight_err" ]; then
  fail_ "T0a" "REFUSING to spawn init.sh — $preflight_err.
            helpers-core.sh::prompt_input would take its NON-interactive branch and
            auto-return defaults, resolving PROJECT_DIR to '$ESCAPE_DIR/' and
            scaffolding a complete project OUTSIDE this fixture. Nothing was run."
  echo ""
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi
pass "T0a: interactive branch reachable (CI/SOIF_NONINTERACTIVE unset) and PROJ is inside \$TMP"

# ── Driver: expect ─────────────────────────────────────────────────────
# Pattern-driven rather than a fixed stream, because two prompts are
# CONDITIONAL on the host: "Install Docker via:" (only when docker is absent)
# and "Proceed with this plan?" (only when the resolver produced an
# auto_install/manual_install row). A positional stream silently desynchronises
# on such a host; a pattern loop does not. Titles set the pending answer and
# the generic "Select [1-N]" prompt sends it, so ordering changes inside
# collect_project_info cannot mis-target an answer either.
run_expect() {
  cat > "$TMP/drive.exp" <<'EXPEOF'
set timeout 900
set projname [lindex $argv 0]
set projdir  [lindex $argv 1]
set pidx     [lindex $argv 2]
set lidx     [lindex $argv 3]
set initsh   [lindex $argv 4]
set ans ""

spawn bash $initsh
expect {
    -re {Project name}                  { send -- "$projname\r";  exp_continue }
    -re {One-sentence description}      { send -- "bl180 pty fixture\r"; exp_continue }
    -re {Project directory}             { send -- "$projdir\r";   exp_continue }
    -re {Platform type:}                { set ans $pidx;          exp_continue }
    -re {Project track:}                { set ans 2;              exp_continue }
    -re {Personal or organizational\?}  { set ans 1;              exp_continue }
    -re {Governance mode:}              { set ans 2;              exp_continue }
    -re {Primary language:}             { set ans $lidx;          exp_continue }
    -re {Install Docker via:}           { set ans 3;              exp_continue }
    -re {Git host:}                     { set ans 4;              exp_continue }
    -re {Repository visibility:}        { set ans 1;              exp_continue }
    -re {Select \[1-[0-9]+\]}           { send -- "$ans\r";       exp_continue }
    -re {Proceed with this plan\?}      { send -- "Y\r";          exp_continue }
    -re {Continue\? \[Y/n\]}            { send -- "Y\r";          exp_continue }
    -re {Paste the HTTPS clone URL}     { send -- "\r";           exp_continue }
    -re {type 'yes' to attest}          { send -- "no\r";         exp_continue }
    -re {Proceed anyway\? \[l/d/N\]}    { send -- "l\r";          exp_continue }

    # ---- Nested Development Guardrails (CDF) installer ----
    # create_project shells out to ~/.claude-dev-framework/scripts/init.sh.
    # Several of ITS prompts are `[ -t 0 ]`-guarded, so they exist ONLY on a
    # pty — they are invisible to every non-interactive fixture in this repo
    # and they will hang an under-fed driver. Answering them is part of what
    # "a real interactive scaffold" means.
    -re {Proceed with framework installation\?} { send -- "y\r"; exp_continue }
    -re {Install Context7 now\?}                { send -- "n\r"; exp_continue }
    -re {Push these to the global framework\?}  { send -- "n\r"; exp_continue }
    # Defensive: the discovery interview is normally skipped because Solo
    # passes --prepopulate, but CDF falls back to it when that file is
    # missing/invalid. Accept every default rather than stalling.
    -re {Are there other branches}              { send -- "n\r"; exp_continue }
    -re {What does the '}                       { send -- "\r";  exp_continue }
    -re {What OS are you developing ON}         { send -- "\r";  exp_continue }
    -re {What platform does this branch TARGET} { send -- "\r";  exp_continue }
    -re {Build tools or constraints}            { send -- "\r";  exp_continue }
    -re {Will this project expand}              { send -- "\r";  exp_continue }

    timeout {
        puts "\nBL180-DRIVER: TIMEOUT — no known prompt matched. Last 400 bytes seen:"
        puts $expect_out(buffer)
        catch { exec kill -9 [exp_pid] }
        exit 3
    }
    eof { }
}
catch wait result
exit [lindex $result 3]
EXPEOF
  expect -f "$TMP/drive.exp" \
    "bl180pty" "$PROJ" "$PLATFORM_IDX" "$LANGUAGE_IDX" "$INIT" > "$TRANSCRIPT" 2>&1
  echo "$?"
}

# ── Driver: script(1) fallback ─────────────────────────────────────────
# BEST-EFFORT, and deliberately so: script(1) allocates a pty but offers no
# pattern matching, so this is a positional stream and a positional stream
# cannot be correct in the presence of CONDITIONAL prompts. Two are benign —
# the tool-plan "Proceed with this plan?" and the extra "y" below are
# self-correcting, because if the plan prompt is absent the surplus answer
# lands on a prompt_choice, which rejects it ("Invalid choice") and re-reads.
# Two are NOT: "Install Docker via:" (docker-less host) and CDF's
# "Install Context7 now?" (context7 not configured) both shift every later
# answer by one. On such a host this driver fails LOUDLY at T1 with the
# transcript tail rather than passing vacuously — install `expect`, which is
# the supported driver, to run the test there.
#
# Answers are lowercase "y" on purpose: the nested CDF installer tests
# `[ "$proceed" != "y" ]` and ABORTS on "Y".
run_script_fallback() {
  cat > "$TMP/answers.txt" <<ANSEOF
bl180pty
bl180 pty fixture
$PLATFORM_IDX
2
1
2
$LANGUAGE_IDX
$PROJ
y
y
y
4
1

ANSEOF
  if script -q /dev/null true </dev/null >/dev/null 2>&1; then
    # BSD/macOS: script [-q] file command [args...]
    script -q /dev/null bash "$INIT" < "$TMP/answers.txt" > "$TRANSCRIPT" 2>&1
  else
    # util-linux: script -q -c "command" file
    script -q -c "bash '$INIT'" /dev/null < "$TMP/answers.txt" > "$TRANSCRIPT" 2>&1
  fi
  echo "$?"
}

echo "T0: driving a REAL interactive init.sh over a pty (driver: $DRIVER)"
if [ "$DRIVER" = "expect" ]; then
  INIT_RC="$(run_expect)"
else
  INIT_RC="$(run_script_fallback)"
fi
echo "      init.sh rc=$INIT_RC, project dir=$PROJ"

# ── T0b: POST-RUN ESCAPE DETECTOR — ordered BEFORE T1 on purpose ────────
# T1 exits 1 the moment the fixture manifest is missing, so anything after it
# never runs on the failing path. An escape is EXACTLY that failing path, which
# is why the escape has to be diagnosed here rather than below: otherwise the
# only message an operator sees is "no manifest at <fixture path>", which names
# the one directory the project was NOT written to.
#
# .claude/manifest.json is the decisive scaffold artifact (create_project +
# bl030_finalize_init write it). It has no legitimate reason to exist in the
# checkout's parent, so this is a precise detector, not a heuristic.
echo "T0b: the run stayed inside the fixture (no scaffold in the checkout's parent)"
if [ -e "$ESCAPE_DIR/.claude/manifest.json" ]; then
  fail_ "T0b" "ESCAPE — a project was scaffolded into '$ESCAPE_DIR', OUTSIDE this
            fixture's mktemp -d ('$TMP'). This is the R-WPA-1 failure mode:
            helpers-core.sh::prompt_input took its non-interactive branch, so
            PROJECT_NAME resolved to \"\" and PROJECT_DIR to '$ESCAPE_DIR/'.
            Remove that directory by hand — it was written by this test run."
else
  pass "T0b: no .claude/manifest.json in '$ESCAPE_DIR' — nothing escaped the fixture"
fi

# ── T1: the scaffold actually happened ─────────────────────────────────
# Guards every assertion below from passing vacuously on a run that never got
# past the wizard.
echo "T1: the interactive run reached project creation"
if [ -f "$PROJ/.claude/manifest.json" ]; then
  pass "T1: manifest.json exists — create_project ran"
else
  fail_ "T1" "no manifest at $PROJ/.claude/manifest.json (driver=$DRIVER rc=$INIT_RC); transcript tail: $(tail -20 "$TRANSCRIPT" 2>/dev/null | tr '\n' '|')"
  echo ""
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi

# ── T2: the combo the fed answers were meant to select ─────────────────
# Neither manifest.json nor phase-state.json stores platform/language, so pin
# against init.sh's OWN resolved-combo line (collect_project_info's summary —
# the same string the aggregator's BL-136 F1 assertion uses) and corroborate
# it with a filesystem artifact that only the 'web' answer produces. Without
# this, a drifted ordinal would scaffold some OTHER project shape and every
# assertion below would still pass, pinning the wrong thing.
echo "T2: fed answers selected the intended project shape"
combo_ok=0
grep -q "Platform: web | Track: standard | Language: typescript" "$TRANSCRIPT" 2>/dev/null && combo_ok=1
if [ "$combo_ok" = "1" ] && [ -f "$PROJ/docs/platform-modules/web.md" ]; then
  pass "T2: resolved combo is web / standard / typescript (+ web platform module on disk)"
else
  fail_ "T2" "derived ordinals drifted — combo line found=$combo_ok, web platform module present=$([ -f "$PROJ/docs/platform-modules/web.md" ] && echo yes || echo no)"
fi

# ── T2b: the run really was INTERACTIVE ────────────────────────────────
# The whole point is that this exercises the arm --non-interactive never
# takes. helpers-core.sh::prompt_input emits a "Non-interactive context:"
# warning whenever it auto-returns a default instead of reading — its absence
# is positive proof the pty was honoured and the wizard truly prompted.
echo "T2b: the wizard ran on the interactive arm (no prompt_input fallbacks)"
if grep -q "Non-interactive context: prompt_input" "$TRANSCRIPT" 2>/dev/null; then
  fail_ "T2b" "prompt_input took its NON-interactive branch — the pty was not honoured, so this run does not exercise the BL-180 arm"
else
  pass "T2b: prompt_input read from the pty (no non-interactive fallback warning)"
fi

# ── T3: THE DEFECT — manifest enforcement_level ────────────────────────
# Pre-BL-180 this was the empty string, which is strictly WORSE than absent:
# `jq -e '.enforcement_level'` exits 0 on "", so upgrade-project.sh's BL-030
# backfill skipped the very project it was written to repair (see
# # BL-180-BACKFILL-EMPTY in scripts/upgrade-project.sh).
echo "T3: manifest enforcement_level is resolved (not the empty string)"
level="$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json" 2>/dev/null)"
if [ "$level" = "strict" ]; then
  pass "T3: enforcement_level=strict"
else
  fail_ "T3" "enforcement_level='$level' (pre-BL-180 this was \"\")"
fi

# ── T4: the strict-mode filesystem gate is actually ON DISK ────────────
# The manifest value is only a claim; this is the enforcement it is supposed
# to imply. verify-install.sh --auto-fix passes 83/83 either way because it
# checks the INSTALLER was copied, never that the HOOK was installed — so this
# assertion is the only thing standing between "reported strict" and
# "actually gated".
echo "T4: .git/hooks/framework-gate.sh installed"
if [ -f "$PROJ/.git/hooks/framework-gate.sh" ]; then
  pass "T4: framework-gate.sh present"
else
  fail_ "T4" "framework-gate.sh ABSENT — strict enforcement is hollow"
fi

# ── T5: the gate is actually WIRED into pre-commit ─────────────────────
# A gate script nobody calls is the BL-112 hollow-gate class.
#
# ASSERT THE SENTINEL, NOT THE FILENAME. The first cut of this case grepped
# for "framework-gate.sh" and PASSED under the mutation proof with the gate
# provably absent — scripts/lib/hook-templates.sh names framework-gate.sh in
# explanatory COMMENTS that are emitted into every generated pre-commit hook,
# strict or not. Only install-filesystem-gates.sh's MARK_OPEN sentinel is
# written exclusively by an actual --install, so that is the load-bearing
# string (the same one the BL-180 filing's A/B counted: 0 interactive vs 1
# non-interactive).
echo "T5: pre-commit invokes the gate"
if [ -f "$PROJ/.git/hooks/pre-commit" ] \
   && grep -qF "SOIF framework gate (BL-030)" "$PROJ/.git/hooks/pre-commit"; then
  pass "T5: .git/hooks/pre-commit carries the installed-gate sentinel"
else
  fail_ "T5" "pre-commit lacks the 'SOIF framework gate (BL-030)' block — the gate was never installed"
fi

# ── T6: the bypass-audit birth row records the real level ──────────────
# prepare_initial_state_for_commit stamps enforcement_level_at_event from the
# same variable; pre-BL-180 it recorded "" and the audit trail lied from the
# project's first row onward.
echo "T6: bypass-audit init row records the resolved level"
if [ -f "$PROJ/.claude/bypass-audit.json" ]; then
  row_level="$(jq -r '[.[] | select(.type == "enforcement_level_set")][0].enforcement_level_at_event // "MISSING"' \
    "$PROJ/.claude/bypass-audit.json" 2>/dev/null)"
  if [ "$row_level" = "strict" ]; then
    pass "T6: enforcement_level_set row records 'strict'"
  else
    fail_ "T6" "audit row enforcement_level_at_event='$row_level'"
  fi
else
  fail_ "T6" "no .claude/bypass-audit.json"
fi

# ── T7: hermeticity self-check ─────────────────────────────────────────
# Prove the run really did not attach a remote. If this ever fails, the test
# has started touching a real host and must be fixed before anything else.
#
# THE EMPTY STRING MUST NOT BE THE PASS CONDITION ON ITS OWN. `git -C "$PROJ"
# remote -v 2>/dev/null` prints NOTHING and exits non-zero when $PROJ is not a
# git repository at all — indistinguishable from a healthy "no remotes" — so
# discarding stderr and testing only `-z` made this case pass for the wrong
# reason. Require the repo to exist AND the command to succeed before an empty
# result is allowed to mean anything.
echo "T7: no git remote was attached (hermeticity self-check)"
remotes=""
remotes_rc=0
remotes="$(git -C "$PROJ" remote -v 2>&1)" || remotes_rc=$?
if [ ! -d "$PROJ/.git" ]; then
  fail_ "T7" "'$PROJ' is not a git repository — 'no remotes' here would be vacuous, not hermetic"
elif [ "$remotes_rc" -ne 0 ]; then
  fail_ "T7" "git remote -v failed (rc=$remotes_rc): $(echo "$remotes" | tr '\n' '|')"
elif [ -z "$remotes" ]; then
  pass "T7: \$PROJ is a git repo and git remote -v is empty"
else
  fail_ "T7" "a remote was attached: $(echo "$remotes" | tr '\n' '|')"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
