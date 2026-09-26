#!/usr/bin/env bash
# scripts/lib/adopt/adopt-guardrails.sh — `## BL-296:` row 33: the Development
# Guardrails for Claude Code, installed into an adopted project.
#
# DECIDED 2026-09-18 (Karl): an adoptee receives the Guardrails, as a scaffolded
# project does. Built 2026-09-25 on his go-ahead.
#
# THE SAME INSTALLER init.sh RUNS: `~/.claude-dev-framework/scripts/init.sh`,
# with the flags init.sh passes (`--prepopulate`, `--skip-plugin-check`), stdin
# from /dev/null so every one of its prompts takes its non-interactive arm (all
# are guarded by `[ -t 0 ]`), and NO `--profile`: the platform is decided in the
# assessment, so the installer's own detection picks one from the project's
# files, as it does in a terminal-less run.
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
  local root="$1" report="$2" dir branch lang ver disc before rc rel
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
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  ( cd "$root" && bash "$dir/scripts/init.sh" --prepopulate "$disc" --skip-plugin-check </dev/null ) \
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
  # Everything the installer wrote is part of the adoption commit, as it is
  # part of a scaffolded project's first commit.
  while IFS= read -r rel; do
    [ -n "$rel" ] && adopt_record_write "$rel"
  done <<FILES
$(cd "$root" && find .claude/framework .claude/project -type f 2>/dev/null | LC_ALL=C sort)
.claude/manifest.json
.claude/settings.json
FILES
  ver="$(jq -r '.frameworkVersion // "unknown"' "$root/.claude/manifest.json" 2>/dev/null)"
  ADOPT_GUARDRAILS_RESULT="installed, version $ver, profile $(jq -r '.profile // "unknown"' "$root/.claude/manifest.json" 2>/dev/null)"
  adopt_note "Installed the Guardrails (version $ver, profile $(jq -r '.profile // "unknown"' "$root/.claude/manifest.json" 2>/dev/null)) —"
  adopt_note "the same installer a new project runs. Its rules and hooks are in .claude/framework/."
  return 0
}
