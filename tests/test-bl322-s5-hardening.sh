#!/usr/bin/env bash
# tests/test-bl322-s5-hardening.sh — `## BL-322:` S5: a CI fixture that leaked
# state between suites, made hermetic and pinned.
#
# THE DEFECT. tests/test-bl141-commitmsg-repair.sh,
# tests/test-bl145-hook-symlink-hookspath.sh and tests/test-pr-review-gate.sh
# ran `verify-install.sh --auto-fix` with the runner's REAL HOME, and its
# `fix_framework_clone` cloned the Guardrails (CDF) main from GitHub into
# ~/.claude-dev-framework: a network fetch, a write outside every temp dir, and
# a clone later suites on the same leg silently depended on
# (tests/test-bl320-approval-schema2.sh R10/E1, tests/test-upgrade-cdf-refresh.sh
# T1/T3-T5, tests/test-bl318-g4g6.sh P4/P4m), which skipped anywhere else.
#
# THE FIX. The three suites run with a temp HOME holding a stand-in clone (the
# seam tests/test-bl284-verify-install-context.sh already uses), so `--auto-fix`
# finds one and never fetches. The real-clone cases read ONE pinned fixture
# through tests/test-helpers/cdf-fixture.sh: SOIF_TEST_CDF_FIXTURE, a clone of
# CDF at 4180f22 (v4.4.1) that the unit-shard and full jobs fetch once and check;
# each suite copies it into its own temp dir. Under CI a missing or wrong
# fixture FAILS; locally a suite may fall back to ~/.claude-dev-framework when
# it is new enough and has the history, and otherwise skips.
#
# CASES
#   H1  each of the three runs green with an EMPTY inherited HOME, a `git` that
#       refuses (and logs) any remote URL, stub installers that log, and a dead
#       proxy: no remote is contacted and the inherited HOME stays empty (at
#       `c125f0f` each tried `git clone … claude-dev-framework.git` into it)
#   X1  cdf_fixture_fetch makes a full clone at the pin from a local upstream
#   X2  … and refuses a pin that is not a commit id, a pin the upstream lacks,
#       and a directory that already exists
#   X3  cdf_fixture_copy with SOIF_TEST_CDF_FIXTURE at the pin: a private clone
#       at the pin; writing to it leaves the fixture untouched
#   X4  … with SOIF_TEST_CDF_FIXTURE not at the pin: FAIL (rc 1), CI or not
#   X5  … with CI set and no SOIF_TEST_CDF_FIXTURE: FAIL, even with a good
#       clone in HOME
#   X6  … locally with no SOIF_TEST_CDF_FIXTURE: HOME's clone when it is new
#       enough and has the history (rc 0); SKIP (rc 77) when it is missing,
#       older, or shallow past a needed commit
#   X7  … a pinned fixture that does not meet a suite's need: FAIL (move the pin)
#   W1  the unit-shard and full jobs each fetch the fixture before the tests
#       run, export SOIF_TEST_CDF_FIXTURE, and cannot pass a failed fetch
#   W2  the pin is CDF v4.4.1's full commit id
#   C1  tests/test-upgrade-cdf-refresh.sh under CI with no fixture and an empty
#       HOME: rc 1, its four real-clone cases FAIL naming the fixture, none
#       skips (at `c125f0f`: 2/0/4, rc 0)
#   C2  tests/test-bl320-approval-schema2.sh and tests/test-bl318-g4g6.sh read
#       their clone through cdf_fixture_copy and turn its rc 1 into a FAIL
#       (static: each runs a minute or more; their tallies are on `## BL-322:`)
#   M   mutants of the helper and the three suites, each killed by a named case
#
# Hermetic: temp dirs only; the fixture cases fetch from a local repository.
# Fixture git runs with GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null (a
# runner's config). bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF SOIF_TEST_CDF_FIXTURE 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl322s5.XXXXXX")" || exit 1
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT INT TERM
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""
HELPER=tests/test-helpers/cdf-fixture.sh
PIN_V441=4180f22be0a8b4410aeaa4e65800aed8e2299805
rgit() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git "$@"; }

# ── H: the three verify-install suites touch no network and no inherited HOME ─
# netprobe FW SUITE DIR — run FW's SUITE with DIR/home as an empty HOME, a git
# that refuses any remote URL, stub installers and a dead proxy. Leaves DIR/rc,
# DIR/out, DIR/net.log (one line per refused remote or installer call).
netprobe() {
  local fw="$1" suite="$2" d="$3" realgit="" t="" rc=0
  realgit="$(command -v git)"
  mkdir -p "$d/home" "$d/bin" && : > "$d/net.log" || return 1
  cat > "$d/bin/git" <<SHIM
#!/bin/bash
for a in "\$@"; do
  case "\$a" in
    https://*|http://*|ssh://*|git://*|git@*:*) printf 'git %s\\n' "\$*" >> "$d/net.log"; echo "netprobe: refused remote \$a" >&2; exit 128 ;;
  esac
done
exec "$realgit" "\$@"
SHIM
  chmod +x "$d/bin/git" || return 1
  for t in brew apt-get sudo claude npm npx pip pip3 curl wget uv uvx docker; do
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/net.log"\nexit 1\n' "$t" "$d" > "$d/bin/$t" && chmod +x "$d/bin/$t" || return 1
  done
  ( cd "$fw" && env -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u GIT_CONFIG_GLOBAL -u SOIF_TEST_CDF_FIXTURE \
      HOME="$d/home" PATH="$d/bin:$PATH" https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
      http_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 \
      bash "$suite" </dev/null > "$d/out" 2>&1 ) || rc=$?
  printf '%s' "$rc" > "$d/rc"
}
H_SUITES="tests/test-bl141-commitmsg-repair.sh tests/test-bl145-hook-symlink-hookspath.sh tests/test-pr-review-gate.sh"
case_H1() {   # FW [SUITE…]
  local fw="$1" s="" d="" bad="" left=""
  shift
  for s in ${*:-$H_SUITES}; do
    d="$(newtmp)"
    netprobe "$fw" "$s" "$d" || { bad="$bad [$s: the probe could not be built]"; continue; }
    [ "$(cat "$d/rc")" = 0 ] || bad="$bad [$s: rc $(cat "$d/rc"): $(tail -1 "$d/out")]"
    [ ! -s "$d/net.log" ] || bad="$bad [$s reached out: $(head -1 "$d/net.log" | cut -c1-160) ($(grep -c . "$d/net.log") call(s))]"
    left="$(ls -A "$d/home")"
    [ -z "$left" ] || bad="$bad [$s wrote into the inherited HOME: $(printf '%s' "$left" | tr '\n' ' ')]"
  done
  CASE_DETAIL="$bad"
  [ -z "$bad" ]
}

# ── X: the fixture helper ────────────────────────────────────────────────────
# mk_upstream DIR — a stand-in CDF with three commits: OLD (4.3.0), then the
# version this suite pins to (4.4.1, PIN), then a later one. Sets UP_OLD,
# UP_PIN, UP_NEXT. Serves any commit by id, as GitHub does.
UP_OLD=""; UP_PIN=""; UP_NEXT=""
mk_upstream() {
  local u="$1"
  # The branch is named: X2 fetches it by name, and git's default branch name
  # is a host setting (CLAUDE.md, `# BL-234-FIXTURE-BARE-HEAD`).
  mkdir -p "$u/hooks" && rgit init -q -b master "$u" && rgit -C "$u" config user.email t@t.invalid && rgit -C "$u" config user.name t \
    && rgit -C "$u" config uploadpack.allowAnySHA1InWant true || return 1
  printf '4.3.0\n' > "$u/FRAMEWORK_VERSION"; printf 'echo old\n' > "$u/hooks/a.sh"
  rgit -C "$u" add -A && rgit -C "$u" commit -q -m old || return 1
  UP_OLD="$(rgit -C "$u" rev-parse HEAD)"
  printf '4.4.1\n' > "$u/FRAMEWORK_VERSION"; printf 'echo pin\n' > "$u/hooks/a.sh"
  rgit -C "$u" add -A && rgit -C "$u" commit -q -m pin || return 1
  UP_PIN="$(rgit -C "$u" rev-parse HEAD)"
  printf 'echo next\n' > "$u/hooks/a.sh"
  rgit -C "$u" add -A && rgit -C "$u" commit -q -m next || return 1
  UP_NEXT="$(rgit -C "$u" rev-parse HEAD)"
}
# in_helper FW PIN SCRIPT — SCRIPT run with FW's helper sourced and its pin
# set to PIN (the stand-in's), CI and SOIF_TEST_CDF_FIXTURE as the caller set them.
in_helper() {
  ( . "$1/$HELPER" || exit 90
    CDF_FIXTURE_PIN="$2"
    eval "$3" )
}
case_X1() {   # FW — a full clone at the pin
  local fw="$1" d="" out=""
  d="$(newtmp)"; mk_upstream "$d/up" || { CASE_DETAIL="fixture"; return 1; }
  out="$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null in_helper "$fw" "$UP_PIN" 'cdf_fixture_fetch "'"$d"'/fx" "file://'"$d"'/up"' 2>&1)" \
    || { CASE_DETAIL="the fetch failed: $out"; return 1; }
  [ "$(rgit -C "$d/fx" rev-parse HEAD)" = "$UP_PIN" ] || { CASE_DETAIL="HEAD is not the pin"; return 1; }
  [ "$(rgit -C "$d/fx" rev-parse --is-shallow-repository)" = false ] || { CASE_DETAIL="the clone is shallow"; return 1; }
  rgit -C "$d/fx" cat-file -e "$UP_OLD^{commit}" || { CASE_DETAIL="the history before the pin was not fetched"; return 1; }
  [ "$(tr -d '[:space:]' < "$d/fx/FRAMEWORK_VERSION")" = 4.4.1 ] || { CASE_DETAIL="the work tree is not the pin's"; return 1; }
}
case_X2() {   # FW — the fetch refuses
  local fw="$1" d="" out="" rc=0
  d="$(newtmp)"; mk_upstream "$d/up" || { CASE_DETAIL="fixture"; return 1; }
  # A branch name fetches, and the HEAD check is what refuses it.
  rc=0; out="$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null in_helper "$fw" master 'cdf_fixture_fetch "'"$d"'/a" "file://'"$d"'/up"' 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && grep -qF "not the pin master; refusing" <<< "$out" || { CASE_DETAIL="a branch name as the pin: rc $rc: $out"; return 1; }
  rc=0; out="$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null in_helper "$fw" 0123456789012345678901234567890123456789 'sleep() { :; }; cdf_fixture_fetch "'"$d"'/b" "file://'"$d"'/up"' 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && grep -qF "could not fetch" <<< "$out" || { CASE_DETAIL="a pin the upstream lacks: rc $rc: $out"; return 1; }
  mkdir -p "$d/c"
  rc=0; out="$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null in_helper "$fw" "$UP_PIN" 'cdf_fixture_fetch "'"$d"'/c" "file://'"$d"'/up"' 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && grep -qF "already exists" <<< "$out" || { CASE_DETAIL="an existing directory: rc $rc: $out"; return 1; }
}
# fx_at D REV — D/fx: a full clone of D/up checked out at REV.
fx_at() { rgit clone -q "$1/up" "$1/fx" && rgit -C "$1/fx" -c advice.detachedHead=false checkout -q --detach "$2"; }
# copy_rc FW PIN HOME CI FIXTURE DEST MINVER [REV] — cdf_fixture_copy's rc,
# then a tab, then CDF_FIXTURE_WHY.
copy_rc() {
  local fw="$1" pin="$2" home="$3" ci="$4" fx="$5" dest="$6" min="$7" rev="${8:-}"
  HOME="$home" CI="$ci" SOIF_TEST_CDF_FIXTURE="$fx" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    in_helper "$fw" "$pin" '[ -n "$CI" ] || unset CI; [ -n "$SOIF_TEST_CDF_FIXTURE" ] || unset SOIF_TEST_CDF_FIXTURE
      rc=0; cdf_fixture_copy "'"$dest"'" "'"$min"'" '"${rev:+\"$rev\"}"' || rc=$?
      printf "%s\t%s" "$rc" "$CDF_FIXTURE_WHY"'
}
case_X3() {   # FW — a pinned fixture gives a private clone at the pin
  local fw="$1" d="" r=""
  d="$(newtmp)"; mk_upstream "$d/up" && fx_at "$d" "$UP_PIN" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$d/home"
  r="$(copy_rc "$fw" "$UP_PIN" "$d/home" "" "$d/fx" "$d/dest" 4.4.0 "$UP_OLD")"
  [ "${r%%	*}" = 0 ] || { CASE_DETAIL="rc/why: $r"; return 1; }
  [ "$(rgit -C "$d/dest" rev-parse HEAD)" = "$UP_PIN" ] || { CASE_DETAIL="the copy is not at the pin"; return 1; }
  [ "$(cd "$d/dest" && pwd -P)" != "$(cd "$d/fx" && pwd -P)" ] || { CASE_DETAIL="the copy is the fixture"; return 1; }
  printf 'scribble\n' > "$d/dest/hooks/a.sh"; printf 'x\n' > "$d/dest/new.txt"
  rgit -C "$d/dest" add -A && rgit -C "$d/dest" -c user.email=t@t.invalid -c user.name=t commit -q -m scribble || { CASE_DETAIL="could not write to the copy"; return 1; }
  [ -z "$(rgit -C "$d/fx" status --porcelain)" ] && [ "$(rgit -C "$d/fx" rev-parse HEAD)" = "$UP_PIN" ] \
    && [ "$(cat "$d/fx/hooks/a.sh")" = "echo pin" ] || { CASE_DETAIL="writing to the copy changed the fixture"; return 1; }
  # A copy that cannot be made (the place is taken) is a failure, never a pass.
  mkdir -p "$d/taken" && printf 'x\n' > "$d/taken/f"
  r="$(copy_rc "$fw" "$UP_PIN" "$d/home" "" "$d/fx" "$d/taken" 4.4.0)"
  [ "${r%%	*}" = 1 ] && grep -qF "could not make a private clone" <<< "$r" || { CASE_DETAIL="a copy into a taken directory: $r"; return 1; }
}
case_X4() {   # FW — a fixture not at the pin fails, CI or not
  local fw="$1" d="" r="" ci=""
  d="$(newtmp)"; mk_upstream "$d/up" && fx_at "$d" "$UP_NEXT" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$d/home"
  for ci in "" true; do
    r="$(copy_rc "$fw" "$UP_PIN" "$d/home" "$ci" "$d/fx" "$d/dest$ci" 4.4.0)"
    [ "${r%%	*}" = 1 ] && grep -qF "is not a clone at the pin" <<< "$r" || { CASE_DETAIL="CI='$ci': $r"; return 1; }
  done
}
case_X5() {   # FW — CI with no fixture fails, whatever HOME holds
  local fw="$1" d="" r=""
  d="$(newtmp)"; mk_upstream "$d/up" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$d/home" && rgit clone -q "$d/up" "$d/home/.claude-dev-framework" || { CASE_DETAIL="fixture"; return 1; }
  r="$(copy_rc "$fw" "$UP_PIN" "$d/home" true "" "$d/dest" 4.4.0)"
  [ "${r%%	*}" = 1 ] && grep -qF "CI is set and SOIF_TEST_CDF_FIXTURE is not" <<< "$r" || { CASE_DETAIL="$r"; return 1; }
  [ ! -e "$d/dest" ] || { CASE_DETAIL="it copied HOME's clone anyway"; return 1; }
}
case_X6() {   # FW — locally, HOME's clone when it qualifies, else SKIP
  local fw="$1" d="" r="" h=""
  d="$(newtmp)"; mk_upstream "$d/up" || { CASE_DETAIL="fixture"; return 1; }
  # none
  mkdir -p "$d/h0"; r="$(copy_rc "$fw" "$UP_PIN" "$d/h0" "" "" "$d/d0" 4.4.0)"
  [ "${r%%	*}" = 77 ] || { CASE_DETAIL="no clone: $r"; return 1; }
  # a full clone at the newest commit, 4.4.1: used, at its own HEAD
  h="$d/h1"; mkdir -p "$h" && rgit clone -q "$d/up" "$h/.claude-dev-framework" || { CASE_DETAIL="fixture h1"; return 1; }
  r="$(copy_rc "$fw" "$UP_PIN" "$h" "" "" "$d/d1" 4.4.0 "$UP_OLD")"
  [ "${r%%	*}" = 0 ] && [ "$(rgit -C "$d/d1" rev-parse HEAD)" = "$UP_NEXT" ] || { CASE_DETAIL="a qualifying clone: $r"; return 1; }
  # older than needed
  r="$(copy_rc "$fw" "$UP_PIN" "$h" "" "" "$d/d2" 4.5.0)"
  [ "${r%%	*}" = 77 ] && grep -qF "these cases need 4.5.0 or later" <<< "$r" || { CASE_DETAIL="too old: $r"; return 1; }
  # depth 1: the needed commit is not in its history
  h="$d/h3"; mkdir -p "$h" && rgit clone -q --depth 1 "file://$d/up" "$h/.claude-dev-framework" || { CASE_DETAIL="fixture h3"; return 1; }
  r="$(copy_rc "$fw" "$UP_PIN" "$h" "" "" "$d/d3" 4.4.0 "$UP_OLD")"
  [ "${r%%	*}" = 77 ] && grep -qF "has no $UP_OLD in its history" <<< "$r" || { CASE_DETAIL="shallow: $r"; return 1; }
  [ ! -e "$d/d2" ] && [ ! -e "$d/d3" ] || { CASE_DETAIL="it copied a clone it skipped"; return 1; }
}
case_X7() {   # FW — a pinned fixture short of the need fails: move the pin
  local fw="$1" d="" r=""
  d="$(newtmp)"; mk_upstream "$d/up" || { CASE_DETAIL="fixture"; return 1; }
  # Fetched as CI fetches it: the pin and its history, nothing after it.
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null in_helper "$fw" "$UP_PIN" 'cdf_fixture_fetch "'"$d"'/fx" "file://'"$d"'/up"' >/dev/null 2>&1 \
    || { CASE_DETAIL="fixture: the fetch failed"; return 1; }
  mkdir -p "$d/home"
  r="$(copy_rc "$fw" "$UP_PIN" "$d/home" "" "$d/fx" "$d/d1" 4.5.0)"
  [ "${r%%	*}" = 1 ] && grep -qF "move the pin" <<< "$r" || { CASE_DETAIL="too old: $r"; return 1; }
  r="$(copy_rc "$fw" "$UP_PIN" "$d/home" "" "$d/fx" "$d/d2" 4.4.0 "$UP_NEXT")"
  [ "${r%%	*}" = 1 ] && grep -qF "move the pin" <<< "$r" || { CASE_DETAIL="a commit after the pin: $r"; return 1; }
}

# ── W: the workflow ──────────────────────────────────────────────────────────
# job_block WF JOB — the job's lines, from `  JOB:` to the next top-level job.
job_block() { awk -v j="  $2:" '$0 == j {f=1; print; next} f && /^  [a-z0-9-]+:$/ {exit} f' "$1"; }
# step_block BLOCK NAME — one step of a job block, by a fixed-string name prefix.
step_block() { NAME="$2" awk 'index($0, "- name: " ENVIRON["NAME"]) {f=1; print; next} f && /^      - name:/ {exit} f' <<< "$1"; }
case_W1() {   # FW — the fetch step, in both jobs, before the tests
  local wf="$1/.github/workflows/tests.yml" job="" b="" s="" bad="" n_fetch="" n_run=""
  for job in unit-shard full; do
    b="$(job_block "$wf" "$job")"
    [ -n "$b" ] || { bad="$bad [$job: no such job]"; continue; }
    s="$(step_block "$b" 'Fetch the pinned Guardrails fixture' | grep -v '^ *#')"
    [ -n "$s" ] || { bad="$bad [$job: no fixture step]"; continue; }
    grep -qF ". $HELPER" <<< "$s" || bad="$bad [$job: the step does not source $HELPER]"
    grep -qE 'cdf_fixture_fetch "\$RUNNER_TEMP/[^"]+"' <<< "$s" || bad="$bad [$job: the step does not run cdf_fixture_fetch into RUNNER_TEMP]"
    grep -qE 'SOIF_TEST_CDF_FIXTURE=\$RUNNER_TEMP/[^ ]+" >> "\$GITHUB_ENV"' <<< "$s" || bad="$bad [$job: SOIF_TEST_CDF_FIXTURE is not exported]"
    grep -qF 'set -euo pipefail' <<< "$s" || bad="$bad [$job: the step does not stop at the first failure]"
    grep -qE '^ *continue-on-error:' <<< "$s" && bad="$bad [$job: continue-on-error]"
    grep -qE '\|\| *(true|:)' <<< "$s" && bad="$bad [$job: a failure is swallowed]"
    n_fetch="$(grep -n -- '- name: Fetch the pinned Guardrails fixture' <<< "$b" | cut -d: -f1)"
    n_run="$(grep -nE -- '- name: Run (fast unit tests|shard)' <<< "$b" | head -1 | cut -d: -f1)"
    [ -n "$n_run" ] && [ "$n_fetch" -lt "$n_run" ] || bad="$bad [$job: the fetch does not come before the tests]"
  done
  CASE_DETAIL="$bad"
  [ -z "$bad" ]
}
case_W2() {   # FW — the pin is CDF v4.4.1, in full
  local p=""
  p="$(sed -n 's/^CDF_FIXTURE_PIN=\([0-9a-f]*\) .*/\1/p' "$1/$HELPER")"
  [ "$p" = "$PIN_V441" ] || { CASE_DETAIL="the pin is '$p', want $PIN_V441"; return 1; }
}

# ── C: the suites that read it ───────────────────────────────────────────────
case_C1() {   # FW — upgrade-cdf-refresh under CI with no fixture fails loudly
  local fw="$1" d="" rc=0 out="" nf="" ns=""
  d="$(newtmp)"; mkdir -p "$d/home"
  out="$( cd "$fw" && env -u SOIF_TEST_CDF_FIXTURE -u CDF_HOME HOME="$d/home" CI=1 bash tests/test-upgrade-cdf-refresh.sh </dev/null 2>&1 )" || rc=$?
  nf="$(grep -cE '^  \[FAIL\] T[1345]\b.*SOIF_TEST_CDF_FIXTURE' <<< "$out")"
  ns="$(grep -c '^  \[SKIP\]' <<< "$out")"
  [ "$rc" -ne 0 ] && [ "$nf" = 4 ] && [ "$ns" = 0 ] || { CASE_DETAIL="rc $rc, $nf of T1/T3/T4/T5 failing on the fixture (want 4), $ns skipped (want 0): $(tail -1 <<< "$out")"; return 1; }
}
case_C2() {   # FW — bl320 and g4g6 read their clone through the helper; rc 1 fails
  local fw="$1" s="" bad=""
  for s in tests/test-bl320-approval-schema2.sh tests/test-bl318-g4g6.sh tests/test-upgrade-cdf-refresh.sh; do
    grep -qF ". \"\$REPO_ROOT/$HELPER\"" "$fw/$s" || bad="$bad [$s does not source the helper]"
    grep -qE '^[^#]*cdf_fixture_copy ' "$fw/$s" || bad="$bad [$s does not call cdf_fixture_copy]"
    grep -qE '^[^#]*(\$HOME|\$\{HOME\}|~)/\.claude-dev-framework' "$fw/$s" && bad="$bad [$s still reads the HOME clone itself, on an executed line]"
    grep -qE '# BL-322-S5-FIXTURE-FAIL$' "$fw/$s" || bad="$bad [$s has no marked rc-1-is-a-FAIL branch]"
  done
  CASE_DETAIL="$bad"
  [ -z "$bad" ]
}

check() {   # LABEL CASE
  CASE_DETAIL=""
  if "$2" "$REPO_ROOT"; then pass "$1${CASE_DETAIL:+ ($CASE_DETAIL)}"; else fail_ "$1" "${CASE_DETAIL:-failed}"; fi
}
echo "=== H — the verify-install suites ==="
check "H1: bl141, bl145 and pr-review-gate pass with no network and leave the inherited HOME empty" case_H1
echo "=== X — the fixture helper ==="
check "X1: the fetch makes a full clone at the pin" case_X1
check "X2: the fetch refuses a branch name, a missing commit and an existing directory" case_X2
check "X3: a fixture at the pin gives a private clone; writing to it leaves the fixture alone" case_X3
check "X4: a fixture not at the pin fails, CI or not" case_X4
check "X5: CI with no fixture fails, even with a good clone in HOME" case_X5
check "X6: locally, HOME's clone when it qualifies; otherwise a skip" case_X6
check "X7: a pinned fixture short of a suite's need fails" case_X7
echo "=== W — the workflow ==="
check "W1: the unit-shard and full jobs fetch the fixture before the tests and cannot pass a failed fetch" case_W1
check "W2: the pin is CDF v4.4.1's full commit id" case_W2
echo "=== C — the suites that read it ==="
check "C1: upgrade-cdf-refresh under CI with no fixture fails its four real-clone cases; none skips" case_C1
check "C2: bl320, g4g6 and upgrade-cdf-refresh read the clone through the helper, and its rc 1 fails" case_C2

# ── M: mutants ───────────────────────────────────────────────────────────────
mk_mirror() {   # SRC DST
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/tests" "$1/init.sh" "$1/README.md" "$1/docs" "$2/" \
    && mkdir -p "$2/.github" && cp -Rp "$1/.github/workflows" "$2/.github/"
}
ends_in() {   # FILE MARKER — how many lines end in MARKER
  MARK="$2" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$1"
}
mutate() {   # FILE MARKER REPLACEMENT — the one line ending in MARKER becomes REPLACEMENT; still parses
  local f="$1"
  [ "$(ends_in "$f" "$2")" = 1 ] || { echo "marker '$2' ends $(ends_in "$f" "$2") line(s) of $f (need 1)"; return 1; }
  MARK="$2" REPL="$3" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' "$f" > "$f.mut" \
    && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(ends_in "$f" "$2")" = 0 ] && [ "$(grep -cxF -- "$3" "$f")" -ge 1 ] || { echo "the replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
}
mutant() {   # ID FILE MARKER REPLACEMENT KILLER WHAT [KILLER-ARGS…]
  local id="$1" file="$2" mark="$3" repl="$4" killer="$5" what="$6" m="" why="" rc=0
  shift 6
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$file" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""; "$killer" "$m" "$@" || rc=$?
  if [ "$rc" -eq 0 ]; then fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes"
  else pass "$id (MUTATION) — $what: killed by ${killer#case_} ($(printf '%s' "${CASE_DETAIL:-failed}" | cut -c1-200))"; fi
}
echo "=== M — mutants ==="
mutant M1 tests/test-bl141-commitmsg-repair.sh '# BL-322-S5-HOME' ':' case_H1 "bl141 keeps the runner's HOME" tests/test-bl141-commitmsg-repair.sh
mutant M2 tests/test-bl145-hook-symlink-hookspath.sh '# BL-322-S5-HOME' ':' case_H1 "bl145 keeps the runner's HOME" tests/test-bl145-hook-symlink-hookspath.sh
mutant M3 tests/test-pr-review-gate.sh '# BL-322-S5-HOME' ':' case_H1 "pr-review-gate keeps the runner's HOME" tests/test-pr-review-gate.sh
mutant M4 tests/test-bl141-commitmsg-repair.sh '# BL-322-S5-STANDIN' ':' case_H1 "bl141's HOME has no stand-in clone, so --auto-fix fetches one" tests/test-bl141-commitmsg-repair.sh
mutant M5 "$HELPER" '# BL-322-S5-FIXTURE-HEAD' '  if false; then' case_X2 "the fetch takes whatever HEAD it got"
mutant M6 "$HELPER" '# BL-322-S5-FIXTURE-ATPIN' '    if false; then' case_X4 "a fixture at any commit is used"
mutant M7 "$HELPER" '# BL-322-S5-FIXTURE-CI' '  elif false; then' case_X5 "CI with no fixture falls back to HOME"
mutant M8 "$HELPER" '# BL-322-S5-FIXTURE-MINVER' '  if false; then' case_X6 "a clone older than the need is used"
mutant M9 "$HELPER" '# BL-322-S5-FIXTURE-REV' '    if false; then' case_X6 "a clone without a needed commit is used"
mutant M10 "$HELPER" '# BL-322-S5-FIXTURE-PRIVATE' '  if false; then' case_X3 "a failed private copy still reports success"
mutant M11 tests/test-upgrade-cdf-refresh.sh '# BL-322-S5-FIXTURE-FAIL' '  *)  skip "$1: $CDF_FIXTURE_WHY" ;;' case_C1 "upgrade-cdf-refresh skips where CI needs it to fail"
mutant M12 tests/test-bl320-approval-schema2.sh '# BL-322-S5-FIXTURE-FAIL' '    *)  SKIP_WHY="$CDF_FIXTURE_WHY"; return 77 ;;' case_C2 "bl320 skips where CI needs it to fail (static)"
mutant M13 tests/test-bl318-g4g6.sh '# BL-322-S5-FIXTURE-FAIL' '  *)  while IFS= read -r l; do skip "$l" "$CDF_FIXTURE_WHY"; done <<< "$(tr '"'|'"' '"'\\n'"' <<< "$P4_LABELS")" ;;' case_C2 "g4g6 skips where CI needs it to fail (static)"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
