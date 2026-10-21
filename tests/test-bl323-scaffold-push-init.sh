#!/usr/bin/env bash
# tests/test-bl323-scaffold-push-init.sh — `## BL-323:` the scaffold push,
# through init.sh itself.
#
# init.sh installs the pre-push review gate and then pushes the scaffold. Before
# BL-323 the gate refused that push (no review on record), the remote kept zero
# refs, and the `main` attempt's error was discarded. These cases run a real
# init.sh against a local bare remote (a pushInsteadOf rewrite, as the
# tests/host-drivers/e2e-init*.test.sh trio does) and read the result from the
# bare and from the project's own .claude/process-state.json.
#
# THIS FILE RUNS init.sh, so it lives in the full lane (CLAUDE.md's membership
# rule); tests/test-bl323-scaffold-push.sh carries the unit-lane cases, the
# helper itself, check-gate.sh --repair, and init.sh's call sites by structure.
#
# I1  --git-host other (the bring-your-own-host branch): the scaffold lands on
#     the bare, init exits 0, one record with the fixed reason.
# I2  a later push of new work, with no review, is still refused.
# I3  --git-host github (a driver's host_push_initial, mock gh): the same.
# I4  --git-host other with the remote missing at init time: the main attempt's
#     own error is shown, the plain-words reason names main, and the deferral's
#     printed remedy is scripts/check-gate.sh --repair; then, with the remote
#     present, the project's own --repair pushes.
# I5  the same failed push, then operator commits, then --repair: refused without
#     a review, no attestation (the escape covers init's scaffold only).
# I6  --allow-existing-dir into a repository that already has history: init
#     records no scaffold, the push is refused without a review, no attestation.
# I7  the same into a directory that held files but no repository; I7b, dotfiles only.
# I8  --no-remote-creation: the record is written and the tree stays one clean commit.
#
# Hermetic: local bare remotes, a mock gh, no network; HOME is a temp dir
# holding a private copy of the pinned Guardrails fixture (`## BL-344:`,
# `## BL-322:` S5), made BEFORE HOME moves. bash 3.2 safe.
set -uo pipefail
_gq() { grep "$@" >/dev/null; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"
REASON='initial scaffold push: framework-generated files only, no operator code to review'
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }
finish() { echo ""; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; [ "$FAILED" -eq 0 ]; exit $?; }

echo "== BL-323 — the scaffold push through init.sh =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; finish; }
done
WORK="$(mktemp -d)"
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# The Guardrails clone init.sh runs: a private copy of the pinned fixture.
# shellcheck source=/dev/null
. "$REPO_ROOT/tests/test-helpers/cdf-fixture.sh" || { echo "FATAL: cannot source tests/test-helpers/cdf-fixture.sh" >&2; exit 1; }
mkdir -p "$WORK/home" || exit 1
CDF_RC=0
cdf_fixture_copy "$WORK/home/.claude-dev-framework" 4.4.0 || CDF_RC=$?
case "$CDF_RC" in
  0)  ;;
  77) skip "every case" "$CDF_FIXTURE_WHY"; finish ;;
  *)  fail_ "fixture" "$CDF_FIXTURE_WHY"; finish ;;   # BL-322-S5-FIXTURE-FAIL
esac
export HOME="$WORK/home"; unset CDF_HOME CLAUDE_CONFIG_DIR XDG_CONFIG_HOME   # BL-344-HOME
export GIT_TERMINAL_PROMPT=0
unset SOLO_PR_REVIEW_ATTESTED SOLO_PR_REVIEW_ATTESTED_REASON GITHUB_BASE_REF
newtmp() { mktemp -d "$WORK/tXXXXXX"; }

# mkbare DIR — the remote. BL-234-FIXTURE-BARE-HEAD: its HEAD names main.
mkbare() { git init -q --bare "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main; }
# gitcfg DIR URL — identity, and a pushInsteadOf that sends URL to DIR/bare.git.
gitcfg() {
  cat > "$1/gitconfig" <<EOF
[user]
  email = bl323@example.invalid
  name = BL323 T
[init]
  defaultBranch = main
[url "file://$1/bare.git"]
  pushInsteadOf = $2
EOF
}
# write_mock_gh DIR — the e2e trio's gh: auth, repo create, protection PUT and GET.
write_mock_gh() {
  mkdir -p "$1/bin"
  cat > "$1/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*|*"--version"*) exit 0 ;;
  *"repo create "*) echo "$MOCK_GH_REPO_URL"; exit 0 ;;
  *"api -X PUT "*protection*) exit 0 ;;
  *"api "*protection*)
    printf '%s\n' '{"required_status_checks":null,"enforce_admins":{"enabled":true},"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}'
    exit 0 ;;
  *) echo "mock gh: unhandled invocation: $*" >&2; exit 127 ;;
esac
STUB
  chmod +x "$1/bin/gh"
}
# run_init DIR HOST URL [flags…] — a real init.sh, personal tier, into DIR/proj.
# Output to DIR/init.log; exit code in INIT_RC.
INIT_RC=0
run_init() {
  local d="$1" host="$2" url="$3"; shift 3
  local extra=()
  if [ "$host" = other ]; then extra=(--remote-url "$url" --branch-protection-attested); fi
  ( cd "$d" && GIT_CONFIG_GLOBAL="$d/gitconfig" PATH="$d/bin:$PATH" GH_TOKEN="e2e-test-sentinel-never-valid" \
      MOCK_GH_REPO_URL="$url" bash "$INIT_SH" --non-interactive --project bl323 --platform web \
      --language typescript --project-dir "$d/proj" --track light --deployment personal \
      --git-host "$host" --visibility private ${extra[@]+"${extra[@]}"} "$@" ) </dev/null >"$d/init.log" 2>&1
  INIT_RC=$?
}
remote_sha() { git -C "$1" rev-parse -q --verify "refs/heads/$2" 2>/dev/null || printf 'none'; }
att_count()  { jq '(.pr_review_attestations // []) | length' "$1/.claude/process-state.json" 2>/dev/null || printf 'none'; }
att_field()  { jq -r --arg f "$2" '(.pr_review_attestations // [])[-1][$f] // ""' "$1/.claude/process-state.json" 2>/dev/null; }
subject_of() { git -C "$1" log -1 --format=%s "$2" 2>/dev/null; }
logtail()    { grep -E 'FAIL|BLOCKED|ATTESTED|Push|push|refspec|Why' "$1" | head -8 | cut -c1-160 | tr '\n' '|'; }
SCAFFOLD_SUBJECT='chore: initialize Solo Orchestrator project'

echo ""
echo "=== I1–I2: the bring-your-own-host branch ==="
D1="$(newtmp)"; URL1="https://example.invalid/bl323/byo.git"
mkbare "$D1/bare.git" && gitcfg "$D1" "$URL1" || { echo "FATAL: I1 fixture" >&2; exit 1; }
run_init "$D1" other "$URL1"
i1_sha="$(remote_sha "$D1/bare.git" main)"
if [ "$INIT_RC" -eq 0 ] && [ "$(subject_of "$D1/proj" "$i1_sha")" = "$SCAFFOLD_SUBJECT" ] \
   && [ "$(att_count "$D1/proj")" = "1" ] && [ "$(att_field "$D1/proj" reason)" = "$REASON" ] \
   && [ "$(att_field "$D1/proj" pushed)" = "$i1_sha" ] && _gq -F '[ATTESTED]' "$D1/init.log" \
   && ! _gq -F 'Push failed' "$D1/init.log"; then
  pass "I1: --git-host other — init exits 0, the scaffold commit is on the bare, and the project carries one dated record with the fixed reason"
else
  fail_ "I1" "rc=$INIT_RC bare main=$i1_sha ($(subject_of "$D1/proj" "$i1_sha")) records=$(att_count "$D1/proj") reason='$(att_field "$D1/proj" reason)' log: $(logtail "$D1/init.log")"
fi

( cd "$D1/proj" && echo work > bl323-work.txt && git add bl323-work.txt \
    && GIT_CONFIG_GLOBAL="$D1/gitconfig" git commit -q --no-verify -m "feat: operator work" ) >/dev/null 2>&1
i2_out="$( cd "$D1/proj" && GIT_CONFIG_GLOBAL="$D1/gitconfig" git push origin main </dev/null 2>&1 )"; i2_rc=$?
if [ "$i2_rc" -ne 0 ] && printf '%s' "$i2_out" | _gq 'no review has ever been recorded' \
   && [ "$(remote_sha "$D1/bare.git" main)" = "$i1_sha" ] && [ "$(att_count "$D1/proj")" = "1" ]; then
  pass "I2: after init, a push of new work with no review is REFUSED — the scaffold's attestation covered that one push"
else
  fail_ "I2" "rc=$i2_rc bare main=$(remote_sha "$D1/bare.git" main) (scaffold $i1_sha) records=$(att_count "$D1/proj") out: $(printf '%s' "$i2_out" | grep -m2 -E 'BLOCKED|ATTESTED|->' | tr '\n' '|')"
fi

echo ""
echo "=== I3: a first-class host's driver ==="
D3="$(newtmp)"; URL3="https://github.com/bl323-test/scaffold.git"
mkbare "$D3/bare.git" && gitcfg "$D3" "$URL3" && write_mock_gh "$D3" || { echo "FATAL: I3 fixture" >&2; exit 1; }
run_init "$D3" github "$URL3"
i3_sha="$(remote_sha "$D3/bare.git" main)"
if [ "$INIT_RC" -eq 0 ] && [ "$(subject_of "$D3/proj" "$i3_sha")" = "$SCAFFOLD_SUBJECT" ] \
   && [ "$(att_count "$D3/proj")" = "1" ] && [ "$(att_field "$D3/proj" reason)" = "$REASON" ] \
   && _gq -F '[ATTESTED]' "$D3/init.log" && ! _gq -F 'Push failed' "$D3/init.log"; then
  pass "I3: --git-host github — the driver's push lands the scaffold commit on the bare and leaves the same record"
else
  fail_ "I3" "rc=$INIT_RC bare main=$i3_sha records=$(att_count "$D3/proj") log: $(logtail "$D3/init.log")"
fi

echo ""
echo "=== I4: a push that fails at init, then check-gate.sh --repair ==="
D4="$(newtmp)"; URL4="https://example.invalid/bl323/later.git"
gitcfg "$D4" "$URL4" || { echo "FATAL: I4 fixture" >&2; exit 1; }
# No bare yet: init's push fails, and --defer-remote-push is the personal tier's
# on-the-record way past it (`# BL-084-TIER-GATE`).
run_init "$D4" other "$URL4" --defer-remote-push
if [ "$INIT_RC" -eq 0 ] && _gq 'does not appear to be a git repository' "$D4/init.log" \
   && _gq -F "the push of 'main' failed" "$D4/init.log" && [ "$(att_count "$D4/proj")" = "0" ] \
   && grep -A1 'DEFERRING the push' "$D4/init.log" >/dev/null && _gq -F 'scripts/check-gate.sh --repair     # pushes the scaffold' "$D4/init.log"; then
  pass "I4a: a failed scaffold push SHOWS the main attempt's own error, names main as the branch that failed, and the deferral names scripts/check-gate.sh --repair"
else
  fail_ "I4a" "rc=$INIT_RC records=$(att_count "$D4/proj") log: $(logtail "$D4/init.log")"
fi
mkbare "$D4/bare.git" || { echo "FATAL: I4 bare" >&2; exit 1; }
i4_out="$( cd "$D4/proj" && GIT_CONFIG_GLOBAL="$D4/gitconfig" bash scripts/check-gate.sh --repair </dev/null 2>&1 )"; i4_rc=$?
i4_head="$(git -C "$D4/proj" rev-parse HEAD 2>/dev/null)"
if [ "$i4_rc" -eq 0 ] && [ "$(remote_sha "$D4/bare.git" main)" = "$i4_head" ] \
   && [ "$(att_count "$D4/proj")" = "1" ] && [ "$(att_field "$D4/proj" reason)" = "$REASON" ]; then
  pass "I4b: the project's own check-gate.sh --repair — the remedy init prints — pushes through the installed hook and leaves the record"
else
  fail_ "I4b" "rc=$i4_rc bare main=$(remote_sha "$D4/bare.git" main) head=$i4_head records=$(att_count "$D4/proj") out: $(printf '%s' "$i4_out" | grep -m4 -E 'FAIL|BLOCKED|refspec|Repair|Why' | cut -c1-160 | tr '\n' '|')"
fi

echo ""
echo "=== I5–I6: the escape covers init's scaffold and nothing else ==="
D5="$(newtmp)"; URL5="https://example.invalid/bl323/later-work.git"
gitcfg "$D5" "$URL5" || { echo "FATAL: I5 fixture" >&2; exit 1; }
run_init "$D5" other "$URL5" --defer-remote-push
i5_init=$INIT_RC
( cd "$D5/proj" && echo 'console.log("operator code")' > app.js && git add app.js \
    && GIT_CONFIG_GLOBAL="$D5/gitconfig" git commit -q --no-verify -m "feat: operator code" ) >/dev/null 2>&1
mkbare "$D5/bare.git" || { echo "FATAL: I5 bare" >&2; exit 1; }
i5_out="$( cd "$D5/proj" && GIT_CONFIG_GLOBAL="$D5/gitconfig" bash scripts/check-gate.sh --repair </dev/null 2>&1 )"; i5_rc=$?
if [ "$i5_init" -eq 0 ] && [ "$i5_rc" -ne 0 ] && [ "$(remote_sha "$D5/bare.git" main)" = "none" ] && [ "$(att_count "$D5/proj")" = "0" ] \
   && printf '%s' "$i5_out" | _gq 'holds commits init.sh did not make' && printf '%s' "$i5_out" | _gq 'no review has ever been recorded'; then
  pass "I5: --repair after a failed init push and operator commits is REFUSED without a review — nothing lands, no attestation"
else
  fail_ "I5" "init rc=$i5_init repair rc=$i5_rc bare main=$(remote_sha "$D5/bare.git" main) records=$(att_count "$D5/proj") out: $(printf '%s' "$i5_out" | grep -m4 -E 'INFO|BLOCKED|ATTESTED|FAIL' | cut -c1-160 | tr '\n' '|')"
fi

D6="$(newtmp)"; URL6="https://example.invalid/bl323/existing.git"
mkbare "$D6/bare.git" && gitcfg "$D6" "$URL6" || { echo "FATAL: I6 fixture" >&2; exit 1; }
mkdir -p "$D6/proj" && ( cd "$D6/proj" && git init -q && echo 'old()' > old.py && git add old.py \
    && GIT_CONFIG_GLOBAL="$D6/gitconfig" git commit -q -m "feat: before init" ) >/dev/null 2>&1
run_init "$D6" other "$URL6" --allow-existing-dir
i6_ref="$(git -C "$D6/proj" rev-parse -q --verify refs/solo-orchestrator/scaffold 2>/dev/null || printf 'none')"
if [ "$INIT_RC" -ne 0 ] && [ "$(remote_sha "$D6/bare.git" main)" = "none" ] && [ "$(att_count "$D6/proj")" = "0" ] \
   && [ "$i6_ref" = "none" ] && _gq 'already held files or history' "$D6/init.log" && _gq 'no review has ever been recorded' "$D6/init.log"; then
  pass "I6: init --allow-existing-dir into a repository with history records no scaffold, and its push is REFUSED without a review — nothing lands, no attestation"
else
  fail_ "I6" "rc=$INIT_RC bare main=$(remote_sha "$D6/bare.git" main) records=$(att_count "$D6/proj") ref=$i6_ref log: $(logtail "$D6/init.log")"
fi

# I7 — --allow-existing-dir into a directory with files but no repository: the
# scaffold commit is a root commit, but it holds the operator's files too.
D7="$(newtmp)"; URL7="https://example.invalid/bl323/files.git"
mkbare "$D7/bare.git" && gitcfg "$D7" "$URL7" || { echo "FATAL: I7 fixture" >&2; exit 1; }
mkdir -p "$D7/proj" && echo 'mine()' > "$D7/proj/mine.py"
run_init "$D7" other "$URL7" --allow-existing-dir
i7_ref="$(git -C "$D7/proj" rev-parse -q --verify refs/solo-orchestrator/scaffold 2>/dev/null || printf 'none')"
if [ "$INIT_RC" -ne 0 ] && [ "$(remote_sha "$D7/bare.git" main)" = "none" ] && [ "$(att_count "$D7/proj")" = "0" ] \
   && [ "$i7_ref" = "none" ] && _gq 'already held files or history' "$D7/init.log"; then
  pass "I7: init --allow-existing-dir into a directory that already held files records no scaffold — the push is REFUSED without a review, no attestation"
else
  fail_ "I7" "rc=$INIT_RC bare main=$(remote_sha "$D7/bare.git" main) records=$(att_count "$D7/proj") ref=$i7_ref log: $(logtail "$D7/init.log")"
fi

# I7b — the same with nothing but a dotfile tree (.github/workflows/): a directory
# whose only entries start with a dot is in use too.
D7b="$(newtmp)"; URL7b="https://example.invalid/bl323/dotfiles.git"
mkbare "$D7b/bare.git" && gitcfg "$D7b" "$URL7b" || { echo "FATAL: I7b fixture" >&2; exit 1; }
mkdir -p "$D7b/proj/.github/workflows" && printf 'on: push\njobs: {}\n' > "$D7b/proj/.github/workflows/operator.yml"
run_init "$D7b" other "$URL7b" --allow-existing-dir
i7b_ref="$(git -C "$D7b/proj" rev-parse -q --verify refs/solo-orchestrator/scaffold 2>/dev/null || printf 'none')"
if [ "$INIT_RC" -ne 0 ] && [ "$(remote_sha "$D7b/bare.git" main)" = "none" ] && [ "$(att_count "$D7b/proj")" = "0" ] \
   && [ "$i7b_ref" = "none" ] && _gq 'already held files or history' "$D7b/init.log"; then
  pass "I7b: init --allow-existing-dir into a directory holding only a dotfile tree records no scaffold — the push is REFUSED without a review, no attestation"
else
  fail_ "I7b" "rc=$INIT_RC bare main=$(remote_sha "$D7b/bare.git" main) records=$(att_count "$D7b/proj") ref=$i7b_ref log: $(logtail "$D7b/init.log")"
fi

# I8 — --no-remote-creation: the record is a ref, so the scaffold stays one clean
# commit, and it names that commit for a later --repair.
D8="$(newtmp)"; gitcfg "$D8" "https://example.invalid/bl323/none.git" || { echo "FATAL: I8 fixture" >&2; exit 1; }
run_init "$D8" github "https://example.invalid/bl323/none.git" --no-remote-creation
i8_ref="$(git -C "$D8/proj" rev-parse -q --verify refs/solo-orchestrator/scaffold 2>/dev/null || printf 'none')"
i8_dirty="$(git -C "$D8/proj" status --porcelain 2>/dev/null)"
if [ "$INIT_RC" -eq 0 ] && [ "$i8_ref" = "$(git -C "$D8/proj" rev-parse HEAD 2>/dev/null)" ] \
   && [ "$(git -C "$D8/proj" rev-list --count HEAD 2>/dev/null)" = "1" ] && [ -z "$i8_dirty" ]; then
  pass "I8: --no-remote-creation — the scaffold record names the one commit, and the tree stays clean (the record is a ref, not a tracked file)"
else
  fail_ "I8" "rc=$INIT_RC ref=$i8_ref head=$(git -C "$D8/proj" rev-parse HEAD 2>/dev/null) commits=$(git -C "$D8/proj" rev-list --count HEAD 2>/dev/null) dirty='$i8_dirty'"
fi

finish
