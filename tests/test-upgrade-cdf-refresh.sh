#!/usr/bin/env bash
# tests/test-upgrade-cdf-refresh.sh — BL-001 regression.
#
# BL-001: scripts/upgrade-project.sh performed NO CDF (Development
# Guardrails) sync. A project that ran the documented upgrade stayed
# frozen at its install-time CDF version, silently missing upstream
# .claude/framework/ hook/rule/gate fixes.
#
# Fix: scripts/lib/cdf-refresh.sh (a thin Solo-side wrapper) is sourced by
# upgrade-project.sh's _refresh_cdf_assets_solo helper and calls
# solo_refresh_cdf, which delegates to the CDF clone's canonical
# refresh_cdf_assets. It re-copies hooks/rules/gates into .claude/framework/,
# marks hook/gate scripts +x, and bumps the manifest
# frameworkVersion/frameworkCommit. The helper is called from TWO distinct
# call sites so both the --backfill-only path (before its short-circuit) and
# the full-upgrade path (after the BL-015 sentinel guard + atomic section-2b
# mutation) sync CDF.
#
# Test scenarios:
#   T1 — Happy path: `upgrade-project.sh --backfill-only` against a fake CDF
#        clone (with a working remote so `git pull --ff-only` succeeds)
#        replaces .claude/framework/hooks|rules|gates with the clone's
#        versions (content match; hook+gate are +x) and bumps the manifest
#        frameworkVersion + frameworkCommit to the clone's values.
#   T2 — Graceful skip: missing CDF clone + non-interactive → the upgrade
#        still exits 0, emits a stderr skip [WARN], and leaves the project's
#        existing .claude/framework/ assets untouched. Guards against
#        re-introducing a silent hard-fail.
#   T3 — Pull-failure resilience: a fake clone with NO remote makes
#        `git pull --ff-only` fail → the refresh warns and still syncs from
#        the clone's current working tree (assets replaced, manifest bumped).
#   T4 — Mutation proof (delegating call): neutralizing solo_refresh_cdf's
#        delegating refresh_cdf_assets call turns the sync into a no-op — the
#        control (real wrapper) refreshes, the mutant leaves the project
#        STALE. Proves the delegating call is load-bearing (T1 goes RED
#        without it), across both call sites.
#   T5 — Full-upgrade call site: a successful `--deployment` upgrade also
#        refreshes CDF from the post-sentinel call site (tier change AND CDF
#        refresh both land).
#   T6 — Mutation proof (graceful-skip return): driving the WRAPPER directly
#        with an absent CDF clone must return 0 and emit the [WARN]. Flipping
#        the wrapper's missing-clone `return 0` to `return 1` makes that
#        direct call return non-zero — proving the graceful-skip exit status
#        is load-bearing (the call-site `|| print_warn` would otherwise mask
#        a return-1 regression).
#
# HERMETICITY
#   T1/T3/T4/T5 need the canonical upstream refresh_cdf_assets implementation.
#   It is located via CDF_REFRESH_SRC (default
#   $HOME/.claude-dev-framework/scripts/cdf-refresh.sh). When that file is
#   absent (e.g. a CI runner without the CDF clone) those scenarios SKIP
#   with a clear notice and the suite still exits 0. T2 and T6 are fully
#   hermetic (the wrapper short-circuits on a missing clone before it needs
#   upstream).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"
WRAPPER="$REPO_ROOT/scripts/lib/cdf-refresh.sh"
UPSTREAM_SRC="${CDF_REFRESH_SRC:-$HOME/.claude-dev-framework/scripts/cdf-refresh.sh}"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1"; SKIPPED=$((SKIPPED + 1)); }

INTEGRATION_OK=1
[ -f "$UPSTREAM_SRC" ] || INTEGRATION_OK=0

# Build a fake CDF clone at $1 with FRAMEWORK_VERSION=$2 and a real upstream
# cdf-refresh.sh, plus a demo hook/rule/gate stamped with the version. When
# $3 == "with-remote", wire a bare origin so `git pull --ff-only` succeeds
# (clean happy path); when "no-remote", omit the remote so the pull FAILS.
make_fake_clone() {
  local clone="$1" version="$2" remote_mode="$3"
  mkdir -p "$clone/scripts" "$clone/hooks" "$clone/rules" "$clone/gates"
  cp "$UPSTREAM_SRC" "$clone/scripts/cdf-refresh.sh"
  echo "$version" > "$clone/FRAMEWORK_VERSION"
  printf '#!/usr/bin/env bash\necho FRESH-HOOK-%s\n' "$version" > "$clone/hooks/demo-hook.sh"
  printf '# fresh rule %s\n' "$version" > "$clone/rules/demo-rule.md"
  printf '#!/usr/bin/env bash\necho FRESH-GATE-%s\n' "$version" > "$clone/gates/demo-gate.sh"
  ( cd "$clone" && git init -q && git config user.email t@t.l && git config user.name t \
      && git add -A && git commit -q -m init ) >/dev/null 2>&1
  if [ "$remote_mode" = "with-remote" ]; then
    local origin="$clone.origin.git"
    git init -q --bare "$origin" >/dev/null 2>&1
    ( cd "$clone" && git remote add origin "$origin" \
        && git push -q -u origin HEAD:main ) >/dev/null 2>&1
  fi
}

# Scaffold a project with STALE .claude/framework/ assets and an OLD pin.
# manifest seeds host + enforcement_level so the host/BL-030 backfills are
# no-ops (keeps the assertion focused on the CDF refresh).
make_stale_project() {
  local proj="$1" old_version="$2"
  mkdir -p "$proj/.claude/framework/hooks" "$proj/.claude/framework/rules" "$proj/.claude/framework/gates"
  printf '#!/usr/bin/env bash\necho STALE-HOOK\n' > "$proj/.claude/framework/hooks/demo-hook.sh"
  printf '# stale rule\n' > "$proj/.claude/framework/rules/demo-rule.md"
  printf '#!/usr/bin/env bash\necho STALE-GATE\n' > "$proj/.claude/framework/gates/demo-gate.sh"
  cat > "$proj/.claude/manifest.json" <<JSON
{"host":"github","frameworkVersion":"$old_version","frameworkCommit":"deadbeefdead","enforcement_level":"strict","deployment":"personal","poc_mode":null}
JSON
  cat > "$proj/.claude/phase-state.json" <<'JSON'
{"track":"standard","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}
JSON
  ( cd "$proj" && git init -q && git config user.email t@t.l && git config user.name t \
      && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: upgrade --backfill-only syncs CDF assets + bumps manifest ==="
# ════════════════════════════════════════════════════════════════════
if [ "$INTEGRATION_OK" = "0" ]; then
  skip "T1: upstream CDF cdf-refresh.sh not found at $UPSTREAM_SRC (set CDF_REFRESH_SRC to enable)"
else
  T=$(mktemp -d); CLONE="$T/cdf"; PROJ="$T/proj"
  make_fake_clone "$CLONE" "99.9.9" with-remote
  make_stale_project "$PROJ" "1.0.0"

  ( cd "$PROJ" && CDF_HOME="$CLONE" bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
  rc=$?

  hook=$(tail -1 "$PROJ/.claude/framework/hooks/demo-hook.sh" 2>/dev/null)
  gate=$(tail -1 "$PROJ/.claude/framework/gates/demo-gate.sh" 2>/dev/null)
  rule=$(cat  "$PROJ/.claude/framework/rules/demo-rule.md" 2>/dev/null)
  hx=$([ -x "$PROJ/.claude/framework/hooks/demo-hook.sh" ] && echo y || echo n)
  gx=$([ -x "$PROJ/.claude/framework/gates/demo-gate.sh" ] && echo y || echo n)
  fv=$(jq -r '.frameworkVersion // empty' "$PROJ/.claude/manifest.json" 2>/dev/null)
  fc=$(jq -r '.frameworkCommit // empty' "$PROJ/.claude/manifest.json" 2>/dev/null)
  clone_head=$(git -C "$CLONE" rev-parse HEAD 2>/dev/null)

  if [ "$rc" = "0" ] \
     && [ "$hook" = "echo FRESH-HOOK-99.9.9" ] \
     && [ "$gate" = "echo FRESH-GATE-99.9.9" ] \
     && [ "$rule" = "# fresh rule 99.9.9" ] \
     && [ "$hx" = "y" ] && [ "$gx" = "y" ] \
     && [ "$fv" = "99.9.9" ] && [ -n "$clone_head" ] && [ "$fc" = "$clone_head" ]; then
    pass "T1: hooks/rules/gates replaced (hook+gate +x); manifest frameworkVersion+Commit bumped to the clone"
  else
    fail_ "T1" "rc=$rc hook='$hook'(x=$hx) gate='$gate'(x=$gx) rule='$rule' fv='$fv' fc='$fc' cloneHEAD='$clone_head'. Log: $(tail -6 "$T/log" 2>/dev/null | tr '\n' '|')"
  fi
  rm -rf "$T"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: missing CDF clone + non-interactive → upgrade still exits 0, warns, keeps assets ==="
# ════════════════════════════════════════════════════════════════════
T=$(mktemp -d); PROJ="$T/proj"
make_stale_project "$PROJ" "1.0.0"
pre_hook=$(tail -1 "$PROJ/.claude/framework/hooks/demo-hook.sh" 2>/dev/null)

( cd "$PROJ" && CDF_HOME="$T/does-not-exist" bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
rc=$?

post_hook=$(tail -1 "$PROJ/.claude/framework/hooks/demo-hook.sh" 2>/dev/null)
warned=$(grep -qiE "skipping CDF asset refresh" "$T/log" && echo y || echo n)
fv=$(jq -r '.frameworkVersion // empty' "$PROJ/.claude/manifest.json" 2>/dev/null)

if [ "$rc" = "0" ] && [ "$warned" = "y" ] && [ "$post_hook" = "$pre_hook" ] && [ "$fv" = "1.0.0" ]; then
  pass "T2: missing clone → upgrade exits 0, emits skip [WARN], leaves existing hooks + pin untouched"
else
  fail_ "T2" "rc=$rc warned=$warned hook_pre='$pre_hook' hook_post='$post_hook' fv='$fv' (expected rc=0, warned, unchanged). Log: $(tail -6 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: git pull --ff-only failure → refresh still proceeds from working tree ==="
# ════════════════════════════════════════════════════════════════════
if [ "$INTEGRATION_OK" = "0" ]; then
  skip "T3: upstream CDF cdf-refresh.sh not found at $UPSTREAM_SRC (set CDF_REFRESH_SRC to enable)"
else
  T=$(mktemp -d); CLONE="$T/cdf"; PROJ="$T/proj"
  make_fake_clone "$CLONE" "88.8.8" no-remote    # no origin → git pull --ff-only fails
  make_stale_project "$PROJ" "1.0.0"

  ( cd "$PROJ" && CDF_HOME="$CLONE" bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
  rc=$?

  hook=$(tail -1 "$PROJ/.claude/framework/hooks/demo-hook.sh" 2>/dev/null)
  fv=$(jq -r '.frameworkVersion // empty' "$PROJ/.claude/manifest.json" 2>/dev/null)
  pullwarn=$(grep -qiE "pull --ff-only failed" "$T/log" && echo y || echo n)

  if [ "$rc" = "0" ] && [ "$pullwarn" = "y" ] \
     && [ "$hook" = "echo FRESH-HOOK-88.8.8" ] && [ "$fv" = "88.8.8" ]; then
    pass "T3: pull --ff-only failure warned, but assets refreshed from working tree + manifest bumped"
  else
    fail_ "T3" "rc=$rc pullwarn=$pullwarn hook='$hook' fv='$fv' (expected rc=0, warned, refreshed to 88.8.8). Log: $(tail -8 "$T/log" 2>/dev/null | tr '\n' '|')"
  fi
  rm -rf "$T"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: mutation proof — neutralizing the delegating call makes the sync a no-op ==="
# ════════════════════════════════════════════════════════════════════
if [ "$INTEGRATION_OK" = "0" ]; then
  skip "T4: upstream CDF cdf-refresh.sh not found at $UPSTREAM_SRC (set CDF_REFRESH_SRC to enable)"
else
  T=$(mktemp -d); CLONE="$T/cdf"
  make_fake_clone "$CLONE" "77.7.7" with-remote

  # -- Control: the real wrapper DOES refresh (the assertion the mutation targets). --
  PROJ_C="$T/proj_control"; make_stale_project "$PROJ_C" "1.0.0"
  ( CDF_HOME="$CLONE"; export CDF_HOME
    . "$WRAPPER"
    solo_refresh_cdf "$PROJ_C" "true" ) > "$T/log_control" 2>&1
  hook_c=$(tail -1 "$PROJ_C/.claude/framework/hooks/demo-hook.sh" 2>/dev/null)
  fv_c=$(jq -r '.frameworkVersion // empty' "$PROJ_C/.claude/manifest.json" 2>/dev/null)
  control_ok=$( { [ "$hook_c" = "echo FRESH-HOOK-77.7.7" ] && [ "$fv_c" = "77.7.7" ]; } && echo y || echo n )

  # -- Mutant: neutralize solo_refresh_cdf's delegating call, expect NO refresh. --
  # Exact whole-line target (grep -Fxq = fixed-string, whole-line). If the
  # wrapper's call shape changes, this fails LOUDLY rather than silently
  # passing on a stale mutation.
  MUT="$T/cdf-refresh.mutant.sh"
  TARGET='  refresh_cdf_assets "$project_root" "$cdf_home" "$non_interactive"'
  if ! grep -Fxq "$TARGET" "$WRAPPER"; then
    fail_ "T4" "mutation target line not found in $WRAPPER — did solo_refresh_cdf's delegating call change? (test needs updating)"
    rm -rf "$T"
  else
    # awk $0==t is an exact string compare — no regex escaping of $ or ".
    awk -v t="$TARGET" '$0==t{print "  : # MUTATION: delegating call neutralized"; next} {print}' \
      "$WRAPPER" > "$MUT"
    if grep -Fxq "$TARGET" "$MUT"; then
      fail_ "T4" "mutation did not take effect — target line still present in the mutant copy"
      rm -rf "$T"
    else
      PROJ_M="$T/proj_mutant"; make_stale_project "$PROJ_M" "1.0.0"
      ( CDF_HOME="$CLONE"; export CDF_HOME
        . "$MUT"
        solo_refresh_cdf "$PROJ_M" "true" ) > "$T/log_mutant" 2>&1
      hook_m=$(tail -1 "$PROJ_M/.claude/framework/hooks/demo-hook.sh" 2>/dev/null)
      fv_m=$(jq -r '.frameworkVersion // empty' "$PROJ_M/.claude/manifest.json" 2>/dev/null)
      mutant_noop=$( { [ "$hook_m" = "echo STALE-HOOK" ] && [ "$fv_m" = "1.0.0" ]; } && echo y || echo n )

      if [ "$control_ok" = "y" ] && [ "$mutant_noop" = "y" ]; then
        pass "T4: control refreshes (hook=FRESH fv=77.7.7); mutant with call removed leaves hook STALE + fv=1.0.0 (call is load-bearing)"
      else
        fail_ "T4" "control_ok=$control_ok (hook_c='$hook_c' fv_c='$fv_c'); mutant_noop=$mutant_noop (hook_m='$hook_m' fv_m='$fv_m')"
      fi
      rm -rf "$T"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: full upgrade (--deployment) also refreshes CDF, AFTER the sentinel/atomic block ==="
# ════════════════════════════════════════════════════════════════════
#
# The full-upgrade path refreshes CDF from a SEPARATE call site — placed
# after the BL-015 pending-approval sentinel guard and the atomic section-2b
# manifest mutation (so a blocked/rolled-back upgrade never touches CDF
# assets). This exercises that call site on a successful personal→org upgrade
# and asserts the tier change AND the CDF refresh both land.
if [ "$INTEGRATION_OK" = "0" ]; then
  skip "T5: upstream CDF cdf-refresh.sh not found at $UPSTREAM_SRC (set CDF_REFRESH_SRC to enable)"
else
  T=$(mktemp -d); CLONE="$T/cdf"; PROJ="$T/proj"
  make_fake_clone "$CLONE" "66.6.6" with-remote
  make_stale_project "$PROJ" "1.0.0"
  # tier-crosscheck-6 gate: personal→organizational refuses unless
  # phase1_artifacts.data_classification is set. Seed it so the upgrade
  # reaches the post-sentinel CDF refresh.
  cat > "$PROJ/.claude/process-state.json" <<'JSON'
{"phase1_artifacts":{"data_classification":"internal","zdr_attested":true,"zdr_attestation_reason":""}}
JSON
  ( cd "$PROJ" && git add -A && git commit -q -m "seed process-state" ) >/dev/null 2>&1

  ( cd "$PROJ" && CDF_HOME="$CLONE" bash "$UPGRADE" --deployment organizational --non-interactive ) > "$T/log" 2>&1
  rc=$?

  ps_dep=$(jq -r '.deployment // empty' "$PROJ/.claude/phase-state.json" 2>/dev/null)
  mf_dep=$(jq -r '.deployment // empty' "$PROJ/.claude/manifest.json" 2>/dev/null)
  hook=$(tail -1 "$PROJ/.claude/framework/hooks/demo-hook.sh" 2>/dev/null)
  fv=$(jq -r '.frameworkVersion // empty' "$PROJ/.claude/manifest.json" 2>/dev/null)

  if [ "$rc" = "0" ] \
     && [ "$ps_dep" = "organizational" ] && [ "$mf_dep" = "organizational" ] \
     && [ "$hook" = "echo FRESH-HOOK-66.6.6" ] && [ "$fv" = "66.6.6" ]; then
    pass "T5: full --deployment upgrade changed tier AND refreshed CDF assets (post-sentinel call site fired)"
  else
    fail_ "T5" "rc=$rc ps_dep='$ps_dep' mf_dep='$mf_dep' hook='$hook' fv='$fv' (expected org + FRESH-HOOK-66.6.6 + fv=66.6.6). Log: $(tail -8 "$T/log" 2>/dev/null | tr '\n' '|')"
  fi
  rm -rf "$T"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: wrapper graceful-skip on missing clone returns 0 + [WARN] (direct, mutation-proof) ==="
# ════════════════════════════════════════════════════════════════════
#
# Fully hermetic — the missing-clone branch short-circuits before the wrapper
# needs upstream, so no CDF clone is required. Drives solo_refresh_cdf
# DIRECTLY (not through upgrade-project.sh) so the return status is observed
# without the call-site's `|| print_warn` masking it.
#
#   Control: real wrapper + absent CDF_HOME → return 0 AND the skip [WARN].
#   Mutant:  flip the missing-clone `return 0` → `return 1`; the SAME direct
#            call now returns non-zero. Proves the graceful-skip exit status
#            is load-bearing (a return-1 regression would be invisible through
#            the call site, but breaks any caller that inspects the status).
T=$(mktemp -d); ABSENT="$T/no-such-cdf-clone"

# -- Control: real wrapper, absent clone → rc=0 + skip [WARN] on stderr. --
( CDF_HOME="$ABSENT"; export CDF_HOME; . "$WRAPPER"; solo_refresh_cdf "$T" "true" ) \
  >"$T/ctl.out" 2>"$T/ctl.err"
ctl_rc=$?
ctl_ok=$( { [ "$ctl_rc" = "0" ] && grep -qiE "skipping CDF asset refresh" "$T/ctl.err"; } && echo y || echo n )

# -- Mutant: flip the missing-clone `return 0` → `return 1`. --
# Exact whole-line anchors (awk $0== compare — no regex escaping of $ [ ] ").
# The anchor line is unique in the wrapper; the flipped line is the FIRST
# `    return 0` inside that if-block.
MUT="$T/cdf-refresh.mutant.sh"
ANCHOR='  if [ ! -f "$upstream" ]; then'
RET_LINE='    return 0'
if ! grep -Fxq "$ANCHOR" "$WRAPPER" || ! grep -Fxq "$RET_LINE" "$WRAPPER"; then
  fail_ "T6" "mutation anchors not found in $WRAPPER — did the missing-clone graceful-skip block change? (test needs updating)"
  rm -rf "$T"
else
  awk -v a="$ANCHOR" -v r="$RET_LINE" '
    $0==a { inb=1 }
    inb && $0==r { print "    return 1  # MUTATION: graceful-skip return flipped"; inb=0; next }
    { print }
  ' "$WRAPPER" > "$MUT"
  if ! grep -Fq "return 1  # MUTATION: graceful-skip return flipped" "$MUT"; then
    fail_ "T6" "mutation did not take effect — awk did not flip the missing-clone return 0"
    rm -rf "$T"
  else
    ( CDF_HOME="$ABSENT"; export CDF_HOME; . "$MUT"; solo_refresh_cdf "$T" "true" ) \
      >/dev/null 2>"$T/mut.err"
    mut_rc=$?
    # Mutant must (a) return non-zero and (b) still emit the [WARN] (only the
    # exit status was flipped, so the diagnostic is unchanged).
    mut_detects=$( { [ "$mut_rc" != "0" ] && grep -qiE "skipping CDF asset refresh" "$T/mut.err"; } && echo y || echo n )
    if [ "$ctl_ok" = "y" ] && [ "$mut_detects" = "y" ]; then
      pass "T6: real wrapper returns 0 + [WARN] on missing clone; flipping return 0→1 makes the direct call return $mut_rc (graceful-skip status is load-bearing)"
    else
      fail_ "T6" "ctl_ok=$ctl_ok (ctl_rc=$ctl_rc); mut_detects=$mut_detects (mut_rc=$mut_rc)"
    fi
    rm -rf "$T"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
