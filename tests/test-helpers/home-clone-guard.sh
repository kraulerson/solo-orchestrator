#!/usr/bin/env bash
# tests/test-helpers/home-clone-guard.sh — the unit lane's check that no suite
# touches the Development Guardrails clone in the runner's HOME (`## BL-344:`).
# Sourced by the unit-shard step, never run.
#
# WHY. scripts/upgrade-project.sh pulls ${CDF_HOME:-$HOME/.claude-dev-framework}
# (`# BL-320-UP-PULL`), so a suite that runs it with the contributor's HOME
# moves the contributor's clone, which every project on that computer reads. A
# runner's HOME holds no clone, the pull is skipped there, and CI stayed green
# while tests/test-bl312-tldr-mode.sh moved Karl's. So the step plants one and
# checks it after every suite.
#
# WHAT IS PLANTED IS NOT THE GUARDRAILS. A git repository on main with one file,
# BL344-PLANTED: no scripts/init.sh, no scripts/cdf-refresh.sh, no
# FRAMEWORK_VERSION. Every reader that needs those (adoption, the refresh,
# the version rows, `## BL-322:` S5's real-clone cases) sees no usable clone,
# as before, so no suite can come to depend on it. (verify-install.sh looks
# for .git alone, so it reports the clone as present.) The cost: a write that only
# happens after those files are found (refresh-guardrails.sh's pull, inside the
# Guardrails' own refresh) is not seen here; the BL-344 audit ran every unit
# suite against a full clone for that.
#
# THE CONTRACT.
#   hcg_plant CLONE WORK
#       CLONE becomes that repository, its origin WORK/up.git one commit ahead
#       (so a pull moves it). Returns 1 with HCG_WHY when CLONE exists (it never
#       replaces a clone it did not plant) or when any step fails.
#   hcg_check
#       0 when nothing under CLONE was written since it was planted; else 1,
#       HCG_WHY naming what was (and the HEAD's move, for a pull). Three
#       comparisons with the plant: no path newer than the stamp, the same
#       paths (a removal under .git changes only the .git directory's time),
#       and the same index entries (`git ls-files -s`: `git rm --cached` and
#       `update-index --chmod` write the index alone). `.git/index` and the
#       `.git` directory's own times do not count: `git status` rewrites the
#       index of a clone it has not seen, entries unchanged, and that is a
#       reader. A missing stamp fails: nothing could be compared.
#   hcg_replant
#       after a 1 from hcg_check, removes what this shell planted and plants it
#       again, so the next suite is judged alone. Refuses (1) in a shell that
#       planted nothing.
#
# A write within the timestamp resolution of the plant is not seen on a
# filesystem that keeps whole seconds; ext4 and APFS keep nanoseconds.
# bash 3.2 safe.

HCG_CLONE=""
HCG_WORK=""
HCG_HEAD=""
HCG_PLANTED=""
HCG_WHY=""

_hcg_paths() { find "$1" | LC_ALL=C sort; }   # BL-344-HCG-PATHLIST

_hcg_git() {
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 \
    git -c user.name=bl344 -c user.email=bl344@example.invalid "$@"
}

hcg_plant() {
  local c="$1" w="$2" s="$2/seed"
  HCG_WHY=""
  if [ -e "$c" ] || [ -L "$c" ]; then   # BL-344-HCG-NOCLOBBER
    HCG_WHY="$c already exists; the check plants its own clone and never replaces one it did not plant"; return 1
  fi
  mkdir -p "$s" && _hcg_git -C "$s" init -q && _hcg_git -C "$s" symbolic-ref HEAD refs/heads/main \
    && printf 'Planted by the unit-shard step (BL-344): a stand-in for the Guardrails clone, so a suite that writes to it fails. Not the Guardrails.\n' > "$s/BL344-PLANTED" \
    && _hcg_git -C "$s" add BL344-PLANTED && _hcg_git -C "$s" commit -q -m 'bl344: planted' \
    && _hcg_git clone -q --bare --no-local "$s" "$w/up.git" 2>/dev/null \
    && _hcg_git clone -q --no-local -b main "$w/up.git" "$c" 2>/dev/null \
    || { HCG_WHY="could not plant a stand-in clone at $c"; return 1; }
  # Only now is origin moved on: the clone's own origin/main stays behind it.
  printf 'one commit past the planted HEAD\n' > "$s/BL344-AHEAD" && _hcg_git -C "$s" add BL344-AHEAD \
    && _hcg_git -C "$s" commit -q -m 'bl344: one commit ahead' || { HCG_WHY="could not make the next commit"; return 1; }
  _hcg_git -C "$s" push -q "$w/up.git" main >/dev/null 2>&1 || { HCG_WHY="could not move the planted upstream on"; return 1; }   # BL-344-HCG-AHEAD
  _hcg_paths "$c" > "$w/paths" && _hcg_git -C "$c" ls-files -s > "$w/index" || { HCG_WHY="cannot record what was planted"; return 1; }   # BL-344-HCG-BASELINE
  : > "$w/stamp" || { HCG_WHY="cannot write $w/stamp"; return 1; }   # BL-344-HCG-STAMP
  HCG_CLONE="$c"; HCG_WORK="$w"; HCG_HEAD="$(_hcg_git -C "$c" rev-parse HEAD)"; HCG_PLANTED=1
  return 0
}

hcg_check() {
  local newer="" head=""
  HCG_WHY=""
  if [ ! -d "$HCG_CLONE/.git" ]; then   # BL-344-HCG-GONE
    HCG_WHY="$HCG_CLONE is gone (it was planted at $HCG_HEAD)"; return 1
  fi
  if [ ! -f "$HCG_WORK/stamp" ]; then   # BL-344-HCG-STAMP-GONE
    HCG_WHY="the stamp it was planted with ($HCG_WORK/stamp) is gone, so a write cannot be told from none"; return 1
  fi
  newer="$(find "$HCG_CLONE" -newer "$HCG_WORK/stamp" 2>/dev/null | grep -vxF -e "$HCG_CLONE/.git/index" -e "$HCG_CLONE/.git")"   # BL-344-HCG-INDEX
  if [ -n "$newer" ]; then   # BL-344-HCG-NEWER
    HCG_WHY="written since it was planted: $(printf '%s\n' "$newer" | cut -c$((${#HCG_CLONE} + 2))- | head -3 | tr '\n' ' ')"   # BL-344-HCG-WHY
  elif [ "$(_hcg_paths "$HCG_CLONE")" != "$(cat "$HCG_WORK/paths" 2>/dev/null)" ]; then   # BL-344-HCG-PATHS
    HCG_WHY="a path under it was added or removed since it was planted"
  elif [ "$(_hcg_git -C "$HCG_CLONE" ls-files -s 2>/dev/null)" != "$(cat "$HCG_WORK/index" 2>/dev/null)" ]; then   # BL-344-HCG-STAGED
    HCG_WHY="its index entries (git ls-files -s) changed since it was planted"
  else
    return 0
  fi
  head="$(git -C "$HCG_CLONE" rev-parse -q --verify HEAD 2>/dev/null)"
  [ "$head" = "$HCG_HEAD" ] || HCG_WHY="its HEAD moved from ${HCG_HEAD:0:7} to ${head:0:7}; $HCG_WHY"   # BL-344-HCG-WHY-HEAD
  return 1
}

hcg_replant() {
  HCG_WHY=""
  [ "$HCG_PLANTED" = 1 ] || { HCG_WHY="this shell planted no clone, so there is none to plant again"; return 1; }   # BL-344-HCG-REPLANT-OWN
  rm -rf "$HCG_CLONE" "$HCG_WORK/up.git" "$HCG_WORK/seed"   # BL-344-HCG-REPLANT-RM
  hcg_plant "$HCG_CLONE" "$HCG_WORK"
}
