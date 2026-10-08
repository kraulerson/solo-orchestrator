#!/usr/bin/env bash
# tests/test-helpers/cdf-fixture.sh — the pinned Development Guardrails (CDF)
# fixture, `## BL-322:` S5. Sourced, never run.
#
# WHY. Some cases need a REAL clone of the Guardrails:
# tests/test-bl320-approval-schema2.sh R10 and E1, tests/test-upgrade-cdf-refresh.sh
# T1, T3, T4 and T5, and tests/test-bl318-g4g6.sh P4, P4m and P4u. Before S5
# they read ~/.claude-dev-framework, which a CI runner had only when an earlier
# suite on the same leg had run `verify-install.sh --auto-fix` with the runner's
# real HOME, and so cloned CDF main over the network into it: depth 1, never
# pinned, and only on `rest`. Anywhere else those cases skipped and the leg
# stayed green.
#
# THE CONTRACT.
#   SOIF_TEST_CDF_FIXTURE   the one variable: a clone of CDF whose HEAD is
#                           CDF_FIXTURE_PIN, with full history. The unit-shard
#                           and full jobs set it ("Fetch the pinned
#                           Guardrails fixture", which runs cdf_fixture_fetch).
#   cdf_fixture_copy DEST MINVER [REV...]
#                           puts a PRIVATE clone at DEST (git clone --no-local,
#                           then the commit checked out), so no suite can
#                           change the fixture, and returns
#       0   DEST is a clone of the fixture; CDF_FIXTURE_FROM says which
#       77  locally, no clone to use: SKIP, CDF_FIXTURE_WHY says why
#       1   FAIL, CDF_FIXTURE_WHY says why: CI is set and SOIF_TEST_CDF_FIXTURE
#           is not; or it names a clone not at the pin; or the pin is older
#           than MINVER or lacks a REV (move the pin); or the copy failed
#   With no SOIF_TEST_CDF_FIXTURE and no CI, ~/.claude-dev-framework is used
#   when its FRAMEWORK_VERSION is at least MINVER and each REV is in its
#   history (a depth-1 clone has none); otherwise 77. Read HOME before a suite
#   points it anywhere else.
#
# bash 3.2 safe. Network only in cdf_fixture_fetch, which only CI runs.

# CDF v4.4.1: the merge of PR #27 (kraulerson/claude-dev-framework), 2026-10-07.
CDF_FIXTURE_PIN=4180f22be0a8b4410aeaa4e65800aed8e2299805   # BL-322-S5-FIXTURE-PIN
CDF_FIXTURE_URL=https://github.com/kraulerson/claude-dev-framework.git
CDF_FIXTURE_WHY=""
CDF_FIXTURE_FROM=""

# _cdf_fixture_ver_ge A B — version A is at least B, both MAJOR.MINOR.PATCH.
_cdf_fixture_ver_ge() {
  local a1="" a2="" a3="" b1="" b2="" b3=""
  case "$1" in [0-9]*.[0-9]*.[0-9]*) ;; *) return 1 ;; esac
  case "$1" in *[!0-9.]*) return 1 ;; esac
  IFS=. read -r a1 a2 a3 <<< "$1"; IFS=. read -r b1 b2 b3 <<< "$2"
  [ "$a1" -gt "$b1" ] && return 0; [ "$a1" -lt "$b1" ] && return 1
  [ "$a2" -gt "$b2" ] && return 0; [ "$a2" -lt "$b2" ] && return 1
  [ "$a3" -ge "$b3" ]
}

# _cdf_fixture_unfit CLONE MINVER [REV...] — why CLONE does not meet the need,
# or nothing when it does.
_cdf_fixture_unfit() {
  local c="$1" min="$2" v="" rev=""
  shift 2
  v="$(git -C "$c" show HEAD:FRAMEWORK_VERSION 2>/dev/null | tr -d '[:space:]')"
  if ! _cdf_fixture_ver_ge "$v" "$min"; then   # BL-322-S5-FIXTURE-MINVER
    printf '%s is at FRAMEWORK_VERSION %s, and these cases need %s or later' "$c" "${v:-(none)}" "$min"; return 0
  fi
  for rev in "$@"; do
    if ! git -C "$c" cat-file -e "$rev^{commit}" 2>/dev/null; then   # BL-322-S5-FIXTURE-REV
      printf '%s has no %s in its history (a shallow clone?), which these cases read' "$c" "$rev"; return 0
    fi
  done
  return 0
}

# cdf_fixture_fetch DIR [URL] — CI's step: DIR becomes a full clone of URL
# (CDF by default) at CDF_FIXTURE_PIN, or the step fails. Refuses a DIR that
# exists, and refuses unless `git rev-parse HEAD` is the pin afterwards.
cdf_fixture_fetch() {
  local d="$1" url="${2:-$CDF_FIXTURE_URL}" head="" try=0
  [ ! -e "$d" ] || { echo "cdf_fixture_fetch: $d already exists; refusing to fetch into it" >&2; return 1; }
  git init -q "$d" || { echo "cdf_fixture_fetch: git init $d failed" >&2; return 1; }
  while :; do
    try=$((try + 1))
    git -C "$d" fetch -q --no-tags "$url" "$CDF_FIXTURE_PIN" && break
    [ "$try" -lt 3 ] || { echo "cdf_fixture_fetch: could not fetch $CDF_FIXTURE_PIN from $url (3 tries)" >&2; return 1; }
    sleep 5
  done
  git -C "$d" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD \
    || { echo "cdf_fixture_fetch: could not check out what was fetched" >&2; return 1; }
  head="$(git -C "$d" rev-parse HEAD 2>/dev/null)"
  if [ "$head" != "$CDF_FIXTURE_PIN" ]; then   # BL-322-S5-FIXTURE-HEAD
    echo "cdf_fixture_fetch: HEAD is '${head:-none}', not the pin $CDF_FIXTURE_PIN; refusing" >&2; return 1
  fi
  [ "$(git -C "$d" rev-parse --is-shallow-repository)" = false ] \
    || { echo "cdf_fixture_fetch: the clone is shallow; refusing" >&2; return 1; }
  echo "cdf_fixture_fetch: $d is CDF at $head ($(git -C "$d" show HEAD:FRAMEWORK_VERSION 2>/dev/null | tr -d '[:space:]'))"
}

# cdf_fixture_copy DEST MINVER [REV...] — see THE CONTRACT above.
cdf_fixture_copy() {
  local dest="$1" min="$2" src="" head="" why="" fixture=0
  shift 2
  CDF_FIXTURE_WHY=""; CDF_FIXTURE_FROM=""
  if [ -n "${SOIF_TEST_CDF_FIXTURE:-}" ]; then
    src="$SOIF_TEST_CDF_FIXTURE"; fixture=1
    head="$(git -C "$src" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)"
    if [ "$head" != "$CDF_FIXTURE_PIN" ]; then   # BL-322-S5-FIXTURE-ATPIN
      CDF_FIXTURE_WHY="SOIF_TEST_CDF_FIXTURE=$src is not a clone at the pin $CDF_FIXTURE_PIN (its HEAD: ${head:-none})"
      return 1
    fi
    CDF_FIXTURE_FROM="the pinned fixture ($src, $CDF_FIXTURE_PIN)"
  elif [ -n "${CI:-}" ]; then   # BL-322-S5-FIXTURE-CI
    CDF_FIXTURE_WHY="CI is set and SOIF_TEST_CDF_FIXTURE is not: the workflow's \"Fetch the pinned Guardrails fixture\" step did not run, so these cases cannot run"
    return 1
  else
    src="$HOME/.claude-dev-framework"
    head="$(git -C "$src" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)"
    [ -n "$head" ] || { CDF_FIXTURE_WHY="no SOIF_TEST_CDF_FIXTURE, and no Guardrails clone at $src"; return 77; }
    CDF_FIXTURE_FROM="$src at $head (no SOIF_TEST_CDF_FIXTURE)"
  fi
  why="$(_cdf_fixture_unfit "$src" "$min" "$@")"
  if [ -n "$why" ]; then
    CDF_FIXTURE_WHY="$why"
    [ "$fixture" = 1 ] && { CDF_FIXTURE_WHY="$why: move the pin"; return 1; }
    return 77
  fi
  git clone -q --no-local --no-checkout "$src" "$dest" 2>/dev/null \
    && git -C "$dest" -c advice.detachedHead=false checkout -q --detach "$head" 2>/dev/null
  # The receipt is the copy's own HEAD, not the clone's exit code.
  if [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null)" != "$head" ]; then   # BL-322-S5-FIXTURE-PRIVATE
    CDF_FIXTURE_WHY="could not make a private clone of $src at $head in $dest"; return 1
  fi
  return 0
}
