#!/usr/bin/env bash
# scripts/lib/adopt/adopt-docs.sh — WP12b: the framework documents an adopted
# project receives.
#
# SPEC: `## BL-242:` D3 — "an adopted project gets documents that match the
# framework's documentation requirements … The old documents are archived in the
# project for historical purposes" — and its 2026-08-31 reach ruling: the
# originals are archived, never deleted, and adoption "must NAME them to the
# operator with an explicit invitation to retrieve content from the archive and
# add it to the new files. The informing is part of the requirement."
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS MATTERS MORE THAN ITS SIZE. `CLAUDE.md` is what an agent reads at the
# start of every session. An adopted project without one starts every session
# with no orientation — which gates exist, which scripts to run, where the
# guides are. Adoption put the gates and scripts in place and then left the one
# file that tells an agent they are there. `adopt_stub_project_docs` said so on
# every run.
#
# WHAT IS WRITTEN, AND WHY EXACTLY THIS SET. The same documents `init.sh` gives
# a scaffolded project at the same moment, through the same sources:
#   CLAUDE.md                 rendered by the SHARED `soif_render_claude_md`
#   FEATURES.md BUGS.md RELEASE_NOTES.md docs/INDEX.md docs/IDENTIFIERS.md
#   docs/archive/README.md    copied from the same templates `init.sh` copies
#   docs/reference/*.md       the eight guides `init.sh` copies — CLAUDE.md
#                             points an agent at three of them by path, so
#                             writing it without them hands over broken
#                             references
# NOT `PROJECT_BIBLE.md` or `PRODUCT_MANIFESTO.md`: `init.sh` does not write
# those either — they are phase outputs, produced when the phases run.
#
# THE "ADAPT OR MERGE" HALF OF D3 IS NOT HERE, AND SAYING SO IS THE POINT. D3
# asks for documents "adapted or merged from what the project already has".
# Adapting prose is judgement, and judgement is Act 3's — the assessment, a
# Claude Code session, which is not built. What a shell step can do honestly is
# lay down the framework's documents, keep every original in the archive, and
# tell the operator by name so the merge can happen — by them now, or by the
# assessment later.
#
# ─────────────────────────────────────────────────────────────────────────────
# NEVER WRITE THROUGH A LINK, NEVER DESTROY WHAT THE ARCHIVE CANNOT GIVE BACK.
# The commit-time hook's review found that a plain `printf >` follows a symlink
# out of the repository (a shared file became 1707 lines of framework hook) and
# writes into a HARDLINK's shared inode. A document is the same shape. So:
#   - a SYMLINK at the path is left alone (the archive collects plain files, so
#     there is no copy to restore from, and the target may be shared);
#   - a READ-ONLY file is left alone;
#   - everything else is written BESIDE the path and RENAMED over it, which
#     replaces the directory entry and leaves any shared inode untouched.
# The guides under docs/reference are written only where ABSENT: they are the
# framework's own copies, a file already there is the operator's, and "write
# only what is not there" keeps them out of I20's overwrite inventory.

# The templates `init.sh` copies verbatim, as "SOURCE-RELATIVE-TO-FRAMEWORK
# DESTINATION" pairs. Spelled once so the writer and the archive's dispositions
# cannot disagree about which documents are replaced.
_adopt_doc_copies() {                                  # BL-242-DOCS-SET
  printf '%s\t%s\n' \
    templates/generated/features.tmpl       FEATURES.md \
    templates/generated/bugs.tmpl           BUGS.md \
    templates/generated/release-notes.tmpl  RELEASE_NOTES.md \
    templates/generated/doc-index.tmpl      docs/INDEX.md \
    templates/generated/identifiers.tmpl    docs/IDENTIFIERS.md \
    templates/generated/archive-readme.tmpl docs/archive/README.md
}
_adopt_doc_references() {                              # BL-242-DOCS-REFERENCE
  printf '%s\n' builders-guide.md governance-framework.md executive-review.md \
    cli-setup-addendum.md user-guide.md messaging-standard.md security-scan-guide.md \
    uat-authoring-guide.md
}

# _adopt_doc_value FILE JQPATH FALLBACK PATTERN — a value from the recorded
# intake, used ONLY if it matches PATTERN. `soif_render_claude_md` puts
# platform, track and language into a sed replacement UNESCAPED, because
# `init.sh` validates them first; adoption must hold the same line, or a value
# carrying `|`, `&` or `\` would corrupt the render.
_adopt_doc_value() {
  local v
  v="$(jq -r "$2 // \"\"" "$1" 2>/dev/null)"
  # A newline defeats the pattern: `grep` passes if ANY line matches, and a
  # second line reaches sed as a command of its own (`w FILE` was measured).
  case "$v" in *[[:cntrl:]]*) printf '%s' "$3"; return 0 ;; esac
  if printf '%s' "$v" | grep -Eq "$4"; then printf '%s' "$v"; else printf '%s' "$3"; fi
}

# _adopt_doc_put ROOT REL SRC — put SRC at REL, or leave REL alone and say why.
# Echoes one of: written | replaced | kept-symlink | kept-readonly.
_adopt_doc_put() {                                     # BL-242-DOCS-PUT
  local root="$1" rel="$2" src="$3" dst tmp had=0
  dst="$root/$rel"
  if [ -L "$dst" ] || adopt_path_under_link "$root" "$rel"; then printf 'kept-symlink'; return 0; fi   # BL-242-PARENT-LINK
  [ -e "$dst" ] && had=1
  if [ "$had" -eq 1 ] && [ ! -w "$dst" ]; then printf 'kept-readonly'; return 0; fi
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  mkdir -p "$(dirname "$dst")" 2>/dev/null || { adopt_refuse "could not create $(dirname "$rel")"; return 1; }
  tmp="$dst.soif-new.$$"
  rm -f "$tmp" 2>/dev/null
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  cp "$src" "$tmp" 2>/dev/null && mv -f "$tmp" "$dst" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; adopt_refuse "could not write $rel"; return 1; }
  adopt_record_write "$rel"
  if [ "$had" -eq 1 ]; then printf 'replaced'; else printf 'written'; fi
}

# adopt_write_framework_docs ROOT — the stage.
adopt_write_framework_docs() {                         # BL-242-DOCS-STAGE
  local root="$1" fw="$ADOPT_FRAMEWORK_ROOT" ip="$1/.claude/intake-progress.json"
  local src rel out replaced="" kept="" name desc platform track language rendered
  command -v soif_render_claude_md >/dev/null 2>&1 \
    || { adopt_refuse "the CLAUDE.md renderer is not loaded (scripts/lib/render-project-docs.sh)"; return 1; }

  # ── CLAUDE.md, through the shared renderer ────────────────────────────────
  # Rendered to a scratch file first and then PUT, so it goes through the same
  # link-and-permission rule as every other document.
  name="${ADOPT_PROJECT_NAME:-this project}"
  desc="$(jq -r '.description // ""' "$ip" 2>/dev/null)"
  [ -n "$desc" ] || desc="Not yet recorded — asked in the assessment."
  platform="$(_adopt_doc_value "$ip" .platform undecided '^[a-z_]+$')"
  track="$(_adopt_doc_value "$ip" .track undecided '^(light|standard|full)$')"
  language="$(_adopt_doc_value "$ip" .language undecided '^[A-Za-z0-9_+#.-]+$')"
  rendered="$ADOPT_WORK/claude-md.rendered"
  soif_render_claude_md "$fw/templates/generated/claude-md.tmpl" "$rendered" \
    "$name" "$desc" "$platform" "$track" "$language" 2 "${ADOPT_DEPLOYMENT:-personal}" \
    || { adopt_refuse "could not render CLAUDE.md from the framework's template"; return 1; }
  # A render that exits 0 having written nothing is not a document.
  [ -s "$rendered" ] || { adopt_refuse "CLAUDE.md rendered empty"; return 1; }
  out="$(_adopt_doc_put "$root" CLAUDE.md "$rendered")" || return 1
  case "$out" in replaced) replaced="$replaced CLAUDE.md" ;; kept-*) kept="$kept CLAUDE.md:${out#kept-}" ;; esac

  # ── the templates init.sh copies ─────────────────────────────────────────
  while IFS="$(printf '\t')" read -r src rel; do
    [ -n "$src" ] || continue
    [ -f "$fw/$src" ] || { adopt_refuse "the framework template $src is missing"; return 1; }
    out="$(_adopt_doc_put "$root" "$rel" "$fw/$src")" || return 1
    case "$out" in replaced) replaced="$replaced $rel" ;; kept-*) kept="$kept $rel:${out#kept-}" ;; esac
  done <<DOCS
$(_adopt_doc_copies)
DOCS

  # ── the reference guides, only where absent ───────────────────────────────
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$fw/docs/$rel" ] || continue
    if [ -e "$root/docs/reference/$rel" ] || [ -L "$root/docs/reference/$rel" ]; then continue; fi
    out="$(_adopt_doc_put "$root" "docs/reference/$rel" "$fw/docs/$rel")" || return 1
    case "$out" in kept-*) kept="$kept docs/reference/$rel:${out#kept-}" ;; esac
  done <<REFS
$(_adopt_doc_references)
REFS

  # ── D3: NAME THEM, AND INVITE THE MERGE ───────────────────────────────────
  # Under its own heading: printed bare, these lines ran straight on from the
  # `NOT DONE` block above them and read as part of it.
  adopt_head "The framework's documents"
  adopt_note "Wrote the framework's documents — CLAUDE.md, FEATURES.md, BUGS.md, RELEASE_NOTES.md,"
  adopt_note "docs/INDEX.md, docs/IDENTIFIERS.md, docs/archive/README.md and the guides in"
  adopt_note "docs/reference/ — except any listed below as left alone, and any guide you already had."
  if [ -n "$replaced" ]; then
    adopt_note "These replaced documents of yours:"
    for rel in $replaced; do adopt_say "     $rel"; done
    adopt_note "Your originals are in ${ADOPT_ARCHIVE_DIR:-the adoption archive}, each with a restore line in its"
    adopt_note "MANIFEST.md. Nothing in them was merged into the new files — copy across anything you"
    adopt_note "want to keep, or leave it for the assessment conversation to fold in."
  fi
  if [ -n "$kept" ]; then
    adopt_note "These were LEFT ALONE, so the framework's version of each is NOT in place:"
    for rel in $kept; do
      case "${rel##*:}" in
        symlink)  adopt_say "     ${rel%:*} — a symlink, or inside a symlinked folder; writing through it could overwrite a file elsewhere" ;;
        readonly) adopt_say "     ${rel%:*} — read-only" ;;
      esac
    done
  fi
  return 0
}
