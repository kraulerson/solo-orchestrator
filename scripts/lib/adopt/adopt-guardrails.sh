#!/usr/bin/env bash
# scripts/lib/adopt/adopt-guardrails.sh — `## BL-296:` row 33: the Development
# Guardrails for Claude Code, installed into an adopted project.
#
# DECIDED 2026-09-18 (Karl): an adoptee receives the Guardrails, as a scaffolded
# project does. Built 2026-09-25 on his go-ahead.
#
# THE SAME INSTALLER init.sh RUNS: `~/.claude-dev-framework/scripts/init.sh`,
# with the flags init.sh passes (`--profile`, `--prepopulate`,
# `--skip-plugin-check`) and stdin from /dev/null so every one of its prompts
# takes its non-interactive arm (all are guarded by `[ -t 0 ]`).
#
# THE PROFILE (# BL-296-ADOPT-PROFILE). init.sh maps the intake's platform; an
# adoptee's platform is decided later, in the assessment, so adoption asks the
# installer's own detect-profile.sh first. Without a TTY that script EXITS 1
# when it recognises nothing — a plain Python, Go, Rust or shell project — and
# the installer with it, which refused every such adoption on a host with the
# clone. So adoption always passes --profile: the detected one, else web-api,
# init.sh's own fallback for a platform it has no profile for, and says so.
#
# THE OPERATOR'S settings.json (# BL-296-ADOPT-SETTINGS). The installer merges
# with `. + {hooks: $h}`, which REPLACES the operator's `.hooks`, and
# overwrites a file that does not parse. Adoption snapshots the file first.
# Afterwards: a file the session layer could compose into gets the operator's
# hooks composed back, theirs first; anything else — not JSON, a non-object
# `hooks`/`permissions`, a symlink — is put back exactly as it was, and the run
# says the Guardrails' hooks are NOT registered. The session layer then sees
# the operator's file, not the installer's rewrite of it.
#
# THREE DIFFERENCES FROM init.sh, EACH ON PURPOSE:
#   1. NO CLONE. init.sh clones the Guardrails when they are missing; adoption
#      does not reach the network unasked, and on the PR lane — which has no
#      clone — it would make every adoption test depend on GitHub. When the
#      clone is absent the run names the two commands that install it later,
#      and the Adoption Record says it was not installed.
#   2. NO `git pull`. Adoption installs what is on disk and records its version.
#   3. RUN BEFORE THE `manifest` STAGE, and this is load-bearing: the installer
#      writes `.claude/manifest.json` with `>` — it REPLACES the file — and the
#      adoption stamp lives there. Before `manifest`, the stamp stage merges into
#      the installer's file; after it, the installer would erase the stamp.
#      (init.sh has the same order for the same reason.)
#
# `SOIF_ADOPT_GUARDRAILS_DIR` points at a different clone — a TEST SEAM, so a
# suite can install a stub instead of depending on the host's clone.

ADOPT_GUARDRAILS_STATE=""    # present | already | absent
ADOPT_GUARDRAILS_RESULT=""   # what the Adoption Record says

_adopt_guardrails_dir() { printf '%s' "${SOIF_ADOPT_GUARDRAILS_DIR:-$HOME/.claude-dev-framework}"; }

# adopt_guardrails_resolve ROOT — before any write: is there a usable clone,
# and does the project already carry the Guardrails?      # BL-296-ADOPT-RESOLVE
adopt_guardrails_resolve() {
  local root="$1" dir
  dir="$(_adopt_guardrails_dir)"
  if [ -d "$root/.claude/framework/hooks" ]; then
    ADOPT_GUARDRAILS_STATE="already"
    ADOPT_GUARDRAILS_RESULT="already installed in this project before adoption; left as it was"
  elif [ -d "$dir/.git" ] && [ -f "$dir/scripts/init.sh" ]; then
    ADOPT_GUARDRAILS_STATE="present"
  else
    ADOPT_GUARDRAILS_STATE="absent"
    ADOPT_GUARDRAILS_RESULT="not installed: no clone at ~/.claude-dev-framework"
  fi
  return 0
}

# adopt_write_guardrails ROOT REPORT — the `guardrails` write stage.  # BL-296-ADOPT-STAGE
adopt_write_guardrails() {
  local root="$1" report="$2" dir branch lang ver disc before rc rel profile=""
  local st="${ADOPT_SESSION_SETTINGS_REL:-.claude/settings.json}" orig="" link="" kind="none" snap h0 h1
  dir="$(_adopt_guardrails_dir)"
  adopt_head "The Development Guardrails for Claude Code"
  case "$ADOPT_GUARDRAILS_STATE" in
    already)
      adopt_note "This project already has the Guardrails (.claude/framework/). They were left as they were."
      return 0 ;;
    absent)
      adopt_note "NOT INSTALLED: there is no clone of the Guardrails at ~/.claude-dev-framework, and"
      adopt_note "adoption does not fetch one over the network. To install them afterwards:"
      adopt_note "  git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework"
      adopt_note "  bash ~/.claude-dev-framework/scripts/init.sh --skip-plugin-check   (from this project's root)"
      return 0 ;;
  esac
  # A symlinked .claude (or a link above it) would take the installer's writes
  # OUTSIDE the project. Not run; said.                # BL-296-ADOPT-LINKED
  if [ -L "$root/.claude" ] || adopt_path_under_link "$root" ".claude/manifest.json"; then
    ADOPT_GUARDRAILS_RESULT="not installed: .claude is a symlink, and the installer would write through it"
    adopt_note "NOT INSTALLED: .claude is a symlink (or inside one), and the installer would write through"
    adopt_note "it to wherever it points. Install by hand once .claude is a plain directory:"
    adopt_note "  bash ~/.claude-dev-framework/scripts/init.sh --skip-plugin-check   (from this project's root)"
    return 0
  fi
  branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'main')"
  lang="$(adopt_report_read "$report" '.stack.languages[0].name // ""')"
  disc="$ADOPT_WORK/guardrails-discovery.json"
  jq -n --arg b "$branch" --arg os "$(uname -s 2>/dev/null)" --arg lang "${lang:-unknown}" --arg today "$(date +%Y-%m-%d)" \
    '{("branch:" + $b): {purpose: "main development branch", devOS: $os,
       targetPlatform: "decided in the adoption assessment", buildTools: $lang},
      futurePlatforms: null, discoveryDate: $today, lastReviewDate: $today}' > "$ADOPT_WORK/guardrails-discovery.json" \
    || { adopt_refuse "could not prepare the Guardrails' discovery answers"; return 1; }
  # The installer backs up what it finds into .claude-backup/<timestamp>/; the
  # adoption archive already holds every original, so — as init.sh does — that
  # backup is removed. Only the one THIS run made: an operator's own
  # .claude-backup stays.
  before="$(ls -1 "$root/.claude-backup" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
  # detect-profile.sh reads only; its one write (saving a new profile) is
  # behind a TTY prompt, and stdin here is /dev/null.   # BL-296-ADOPT-PROFILE
  profile="$( (cd "$root" && bash "$dir/scripts/detect-profile.sh" </dev/null 2>/dev/null) | tail -1)"
  case "$profile" in
    ''|*[!a-z0-9-]*)
      profile="web-api"
      adopt_note "The Guardrails could not tell this project's type from its files, so they were"
      adopt_note "installed with the web-api profile (as a new project with no matching profile is)."
      adopt_note "To change it: bash ~/.claude-dev-framework/scripts/init.sh --reconfigure" ;;
  esac
  # What was there before, so only the installer's own writes are claimed, and
  # the operator's settings.json can be put back.     # BL-296-ADOPT-SETTINGS
  snap="$ADOPT_WORK/guardrails-before.txt"
  : > "$ADOPT_WORK/guardrails-before.txt"
  while IFS= read -r rel; do
    [ -n "$rel" ] && [ -f "$root/$rel" ] && printf '%s %s\n' "$(adopt_sha256 "$root/$rel")" "$rel" >> "$ADOPT_WORK/guardrails-before.txt"
  done <<BEFORE
$(cd "$root" && find .claude/framework .claude/project -type f 2>/dev/null | LC_ALL=C sort)
.claude/manifest.json
$st
BEFORE
  if [ -L "$root/$st" ]; then
    kind="restore"; link="$(readlink "$root/$st")"
  elif [ -f "$root/$st" ]; then
    orig="$ADOPT_WORK/guardrails-settings.orig"
    cp -p "$root/$st" "$ADOPT_WORK/guardrails-settings.orig" || { adopt_refuse "could not keep a copy of $st"; return 1; }
    if jq -e 'type == "object" and ((.permissions == null) or ((.permissions | type) == "object")) and ((.hooks == null) or ((.hooks | type) == "object"))' "$orig" >/dev/null 2>&1; then
      kind="compose"
    else
      kind="restore"
    fi
  fi
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  ( cd "$root" && bash "$dir/scripts/init.sh" --profile "$profile" --prepopulate "$disc" --skip-plugin-check </dev/null ) \
    > "$ADOPT_WORK/guardrails.log" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ] || ! jq -e '.frameworkVersion' "$root/.claude/manifest.json" >/dev/null 2>&1; then   # BL-296-ADOPT-RECEIPT
    adopt_block "the Guardrails installer did not complete (rc $rc): $(tail -1 "$ADOPT_WORK/guardrails.log" 2>/dev/null)"
    return 1
  fi
  for rel in $(ls -1 "$root/.claude-backup" 2>/dev/null); do
    case " $before " in *" $rel "*) continue ;; esac
    rm -rf "$root/.claude-backup/$rel"
  done
  [ -z "$before" ] && rmdir "$root/.claude-backup" 2>/dev/null
  case "$kind" in
    compose)   # the installer's hooks, then every entry of theirs it dropped, per event, theirs first
      jq --slurpfile o "$orig" '
        .hooks = (reduce (($o[0].hooks // {}) | to_entries[]) as $e ((.hooks // {});
          (.[$e.key] // []) as $cur
          | .[$e.key] = ([$e.value[] | select(. as $x | any($cur[]; . == $x) | not)] + $cur)))' \
        "$root/$st" > "$ADOPT_WORK/guardrails-settings.json" \
        && mv "$ADOPT_WORK/guardrails-settings.json" "$root/$st" \
        || { adopt_block "could not compose your $st hooks back after the Guardrails installer; your original is in the archive"; return 1; }
      jq -e --slurpfile o "$orig" '[($o[0].hooks // {}) | to_entries[] | .key as $k | .value[] | {k: $k, v: .}] as $theirs
        | . as $now | all($theirs[]; . as $t | any(($now.hooks[$t.k] // [])[]; . == $t.v))' "$root/$st" >/dev/null 2>&1 \
        || { adopt_block "the Guardrails installer removed hooks of yours from $st and they could not be put back"; return 1; }   # BL-296-ADOPT-SETTINGS-RECEIPT
      ;;
    restore)
      rm -f "$root/$st"
      if [ -n "$link" ]; then ln -s "$link" "$root/$st"; else cp -p "$orig" "$root/$st"; fi \
        || { adopt_block "could not put your $st back after the Guardrails installer; your original is in the archive"; return 1; }
      ;;
  esac
  # What the installer created or changed joins the adoption commit, as it is
  # part of a scaffolded project's first commit. A file it did not touch is
  # not claimed: claiming an operator's file makes I20 read it as replaced.
  while IFS= read -r rel; do
    [ -n "$rel" ] && [ -f "$root/$rel" ] && [ ! -L "$root/$rel" ] || continue
    h0="$(awk -v r="$rel" 'substr($0, index($0, " ") + 1) == r { print $1; exit }' "$snap")"
    h1="$(adopt_sha256 "$root/$rel")"
    [ "$h0" = "$h1" ] || adopt_record_write "$rel"
  done <<FILES
$(cd "$root" && find .claude/framework .claude/project -type f 2>/dev/null | LC_ALL=C sort)
.claude/manifest.json
$st
FILES
  ver="$(jq -r '.frameworkVersion // "unknown"' "$root/.claude/manifest.json" 2>/dev/null)"
  ADOPT_GUARDRAILS_RESULT="installed, version $ver, profile $(jq -r '.profile // "unknown"' "$root/.claude/manifest.json" 2>/dev/null)"
  if [ "$kind" = restore ]; then
    ADOPT_GUARDRAILS_RESULT="$ADOPT_GUARDRAILS_RESULT; hooks not registered ($st left as it was)"
    adopt_note "Your $st is not plain JSON the framework can compose into (or is a symlink), so it"
    adopt_note "was put back exactly as it was. The Guardrails' hooks are NOT registered; add them by hand"
    adopt_note "from a scaffolded project's $st."
  fi
  adopt_note "Installed the Guardrails (version $ver, profile $(jq -r '.profile // "unknown"' "$root/.claude/manifest.json" 2>/dev/null)) —"
  adopt_note "the same installer a new project runs. Its rules and hooks are in .claude/framework/."
  return 0
}
