#!/usr/bin/env bash
# scripts/lib/accumulation.sh — BL-233 WP-B: the predicates that decide whether
# a phase owes a stored memory. Sourced by BOTH scripts/check-phase-gate.sh
# (which BLOCKS on them) and scripts/pre-commit-gate.sh (which WARNS on them).
#
# It is one file because the warning exists to predict the block. If the two
# disagree, the warning is worse than absent: it tells a developer they are fine
# and the gate then stops them. They were two hand-copied literals once, and
# they had already drifted. See `## BL-233:` for that history — it does not
# belong here.
#
# EDITING THE EXEMPT SET: the rule is that anything NOT matched is source work.
# Get the direction right when you add to it. An entry here is a claim that a
# change of that kind produces nothing worth remembering; adding one too many
# silently voids the gate, adding one too few is a nuisance block the operator
# can clear by storing or attesting. Prefer the nuisance.
#
# SYNC SIBLING: scripts/process-checklist.sh::_is_dep_manifest — the dep-manifest
# arm below must stay a superset of it.

# ── What is NOT source work ────────────────────────────────────────────────
#   ^$                 blank lines — `git log --name-only` separates commits
#                      with one, and a blank line matches no extension
#   docs extensions    md/markdown/rst/adoc/txt/tmpl
#   dep manifests      a SUPERSET of _is_dep_manifest: its entries plus the
#                      ecosystems it predates (uv, mix, flake, deno, bun —
#                      BOTH `bun.lock` and the pre-1.2 binary `bun.lockb`,
#                      Podfile, Gopkg). A lockfile bump is not an insight
#   project metadata   package.json, pyproject.toml, tsconfig.json, …
#   dotfile rc files   .eslintrc, .prettierrc.yaml, …
#   .claude/*.json     framework state (phase-state, process-state, manifest);
#                      these churn on every gate run and are not authored work
#   extension-less     LICENSE, README, CODEOWNERS, .gitignore, …
#
# json/yml/yaml/toml are NOT blanket-exempt, and that is the one place this
# deliberately diverges from process-checklist.sh's docs-only rule. A blanket
# exemption meant a Kubernetes, Helm, Ansible or OpenAPI phase counted as
# "nothing owed" — infrastructure as code is authored work, and the docs-only
# bypass answers a different question (does this commit need a Build Loop entry)
# than this gate does (did this phase produce knowledge worth storing).
# Unrecognised structured data therefore fails CLOSED.
_ACCUM_EXEMPT_RE='^$|\.(md|markdown|rst|adoc|txt|tmpl)$|(^|/)(Pipfile(\.lock)?|Gemfile(\.lock)?|Cargo\.lock|go\.(mod|sum)|poetry\.lock|yarn\.lock|pnpm-lock\.yaml|pubspec\.lock|uv\.lock|mix\.lock|flake\.lock|deno\.lock|bun\.lock(b)?|Podfile\.lock|Gopkg\.lock|Package\.resolved|gradle\.lockfile|package-lock\.json|npm-shrinkwrap\.json|packages\.lock\.json|composer\.lock|requirements([-_][^/]*)?\.txt)$|(^|/)(package\.json|composer\.json|tsconfig([.-][^/]*)?\.json|jsconfig\.json|pyproject\.toml|Cargo\.toml|renovate\.json)$|(^|/)\.[A-Za-z0-9_-]+rc(\.(json|ya?ml|toml))?$|(^|/)\.claude/[^/]*\.json$|(^|/)(\.gitignore|\.gitattributes|\.dockerignore|\.editorconfig|\.gitkeep|LICENSE|LICENCE|NOTICE|CODEOWNERS|README|CHANGELOG|AUTHORS|CONTRIBUTING)$'   # BL-233-WPB-EXEMPT-SET

# accum_paths_have_source <newline-separated-paths> — 0 if any path is source.
# A HERE-STRING, never `printf | grep -q`: under `set -o pipefail` that pipeline
# returns 141 ON A MATCH once the payload is big enough (`## BL-238:`), and here
# a spurious 141 would read as "no source work" — the fail-OPEN direction — on
# exactly the large-history repos where the check matters most.
accum_paths_have_source() {
  grep -qvE "$_ACCUM_EXEMPT_RE" <<< "$1"   # BL-233-WPB-SOURCE-NEGATION
}

# accum_file_tracked <path> — does git actually track this file?
#
# ASKED, never inferred. WP-B's first fix reasoned that init.sh writes
# .claude/settings.local.json and `git add -A` commits it. Claude Code adds that
# file to the user's GLOBAL git excludes by design, and generate_gitignore
# COPIES templates/generated/gitignore-base.tmpl (which ignores
# .claude/tool-usage.json) before appending — so BOTH declaration arms were
# absent from every fresh clone and the gate blocked locally while reporting
# NOT CHECKED on CI. Trackedness is a question for git; git answers it.
accum_file_tracked() {
  git ls-files --error-unmatch -- "$1" >/dev/null 2>&1   # BL-233-WPB-TRACKED
}

# accum_requirement_state — echoes tracked | untracked | none.
#
# Three states, not a boolean: "required" and "required everywhere" are
# different facts, and conflating them is what produced the defect above.
#
# PROJECT SCOPE ONLY — never $HOME, even though session-test-gate-check.sh reads
# both scopes. Zero of the 29 suites that drive check-phase-gate.sh at
# current_phase >= 2 redirect HOME, so a host-derived verdict passes on a
# developer box with Qdrant configured and fails on a runner without it:
# `## BL-234:`'s class.
# A FOURTH state, `unreadable`, exists because a corrupt declaration must not
# fold into `none`. `none` says "this project declares no Qdrant MCP server" —
# a claim about CONTENT — and a file that will not parse has had its content
# read by nobody. One missing brace silently turned the gate off while asserting
# a fact it never established.
#
# ALL THREE declaration files get the check. The first cut guarded manifest.json
# and settings*.json and forgot the ledger — the same defect in one of the three
# places it lives, which is this work's recurring failure: fixing the named
# instance instead of the class. `scripts/validate.sh` already warns that
# tool-usage.json is unparseable in practice, so the case is real, not theoretical.
#
# `jq -e 'true'` — and neither of the two obvious alternatives.
#   `jq -e .`     tests the DOCUMENT's truthiness, so valid JSON `null`/`false`
#                 read as corrupt. That was the reported bug.
#   `jq empty`    succeeds on a file holding ZERO documents, so a zero-byte or
#                 whitespace-only file reads as VALID — the fix for the first
#                 bug opened a fail-OPEN hole in its place. A truncated write, a
#                 full disk, or a `>` redirect that died all produce that file.
# A constant filter asks the only question that matters — did the parse RUN —
# and never consults the document's own value.
# Public alias: consumers outside this file call accum_json_readable. Same
# function; the leading-underscore name stays for the internal call sites.
accum_json_readable() {
  _accum_json_ok "$1"
}

_accum_json_ok() {
  jq -e 'true' "$1" >/dev/null 2>&1
}

accum_requirement_state() {
  local _f _tracked_hit=0 _untracked_hit=0 _unreadable=0
  # No jq guard: every caller establishes jq before calling. A guard here would
  # return the PERMISSIVE answer for a tool-availability problem, and it could
  # not fire anyway (`## BL-104:`).

  # .claude/manifest.json is the TRACKED declaration init.sh writes for exactly
  # this purpose; the generated .gitignore does not cover it, so it survives a clone.
  if [ -f ".claude/manifest.json" ]; then
    if ! _accum_json_ok ".claude/manifest.json"; then
      _unreadable=1
    elif [ "$(jq -r '.mcp.qdrant_required // false' ".claude/manifest.json" 2>/dev/null)" = "true" ]; then
      if accum_file_tracked ".claude/manifest.json"; then _tracked_hit=1; else _untracked_hit=1; fi
    fi
  fi

  for _f in ".claude/settings.local.json" ".claude/settings.json"; do   # BL-233-WPB-SCOPE
    [ -f "$_f" ] || continue
    if ! _accum_json_ok "$_f"; then
      _unreadable=1
    elif jq -e '(.mcpServers // {}) | (has("qdrant") or has("mcp-server-qdrant"))' "$_f" >/dev/null 2>&1; then
      if accum_file_tracked "$_f"; then _tracked_hit=1; else _untracked_hit=1; fi
    fi
  done

  # The ledger is the weakest arm: `startup` wipes it, and in a pre-BL-236
  # project it may even be TRACKED, which would make scratch authoritative.
  # It is kept only so a project that adopted Qdrant after init is still covered,
  # and it can never upgrade the verdict to `tracked`.
  if [ -f ".claude/tool-usage.json" ]; then
    if ! _accum_json_ok ".claude/tool-usage.json"; then
      _unreadable=1   # BL-233-WPB-LEDGER-UNREADABLE
    elif [ "$(jq -r '.mcp_requirements.qdrant_required // false' ".claude/tool-usage.json" 2>/dev/null)" = "true" ]; then
      _untracked_hit=1   # BL-233-WPB-LEDGER-NEVER-TRACKED
    fi
  fi

  if [ "$_tracked_hit" -eq 1 ]; then printf 'tracked'; return 0; fi
  if [ "$_untracked_hit" -eq 1 ]; then printf 'untracked'; return 0; fi
  # A real declaration outranks an unreadable one; only fall to `unreadable`
  # when nothing legible said yes.
  if [ "$_unreadable" -eq 1 ]; then printf 'unreadable'; return 0; fi
  printf 'none'
  return 0
}
