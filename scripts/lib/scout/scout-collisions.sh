#!/usr/bin/env bash
# scripts/lib/scout/scout-collisions.sh — §8.2's `collisions` section: what the
# adoptee already has that the framework's writers would land on, each sorted
# into one of §7.1's four buckets. REPORT-ONLY. Scout still writes nothing.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §1.2 (the measured
# collision surface — this file's inventory is that table), §7.1 (the four
# buckets, and the vocabulary is reused rather than reinvented), §7.2 (the
# archived-hook description), §7.3 (the archive's own secret hazard), §7.4 (the
# CI carve-out and its four SDLC-undermining detector rules), §7.5 (project
# files: keep theirs), §8.2 (the schema).
#
# M5: sources nothing. See scripts/lib/scout/scout-core.sh's header.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE INVENTORY IS THE DESIGN'S TABLE, NOT A GUESS. §1.2 read every write in
# the scaffolder from its write primitive — `cat >` / `cp` / `printf >` versus
# a marker-guarded `>>` — so the behaviour-on-a-pre-existing-file column is
# measured, not inferred. This file reports which of those surfaces the target
# actually HAS. A surface that is absent produces NO ROW: "we looked and there
# is nothing there" is expressed by the row not existing, never by a row saying
# so, because a reader counting rows must be counting real collisions.
#
# ─────────────────────────────────────────────────────────────────────────────
# CONTENT IS NEVER QUOTED INTO THE REPORT, AND THAT IS THE SAME RULE AS §6.2.
#
# Two surfaces here would naively want to quote bytes, and both are refused:
#
#   THE HOOK DESCRIPTION. §7.2 requires a what-it-invokes description for every
#   archived git hook, and §7.3 names the hazard in as many words — the archive
#   promotes an untracked `.git/hooks/` file into version control, and a
#   hand-rolled hook can contain a token. So the description is assembled from
#   a FIXED TOOL VOCABULARY: the generator emits names it recognises and
#   nothing else. A hook line reading `export AWS_KEY=…` contributes exactly
#   nothing, because no allowlisted token matches it. It is advisory and says
#   so — a hook can do anything, and this is a summary, not a specification.
#
#   THE CI FINDINGS. A workflow line can carry a credential just as easily as a
#   hook line. Each finding therefore reports the RULE, the PATH and the LINE
#   NUMBER — enough to open the file at the right place — and never the matched
#   text. §6.2's doctrine, applied to a surface §6.2 does not mention.

# ── The four buckets (§7.1), spelled once ───────────────────────────────────
# archive-and-replace  their AI-layer surfaces and their git hooks: inventory,
#                      archive with a MANIFEST, install the clean set, disclose
#                      plainly, permit recorded re-adds
# marker-composed      where the framework already composes by marker-fenced
#                      append, with an uninstall
# audit-only           their pipelines: never archived, never touched (§7.4)
# keep-theirs          project files; the framework's artifacts adapt (§7.5)

# _scout_col_add WORK PATH CLASS BUCKET DESC NOTE FINDINGS — one inventory row.
#
# AN EMPTY COLUMN IS WRITTEN AS `-`, AND THAT IS NOT COSMETIC. Tab is an IFS
# WHITESPACE character, so `IFS=$'\t' read -r a b c` collapses a run of tabs
# into ONE delimiter even when IFS was set explicitly — a row with an empty
# middle field silently shifts every column after it into the wrong variable.
# Measured here: the CI rows' empty description put the note into `description`
# and the rule list into `note`, and the report emitted `findings: []` for a
# workflow that had a finding. The reader turns `-` back into an empty string.
_scout_col_add() {
  local desc="$5" note="$6" findings="$7"
  [ -n "$desc" ]     || desc="-"
  [ -n "$note" ]     || note="-"
  [ -n "$findings" ] || findings="-"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$desc" "$note" "$findings" >> "$1/colentries"
}

# _scout_col_unblank VALUE — the reader half of the `-` sentinel above.
_scout_col_unblank() {
  [ "$1" = "-" ] && { printf ''; return 0; }
  printf '%s' "$1"
}

# _scout_hook_vocabulary — the tool names a hook description may contain.
#
# A CLOSED LIST IS THE WHOLE MECHANISM. Anything a hook invokes that is not on
# this list is reported as "and other commands" rather than named, which costs
# a little fidelity and buys the guarantee that no byte of a hook can reach the
# report through this path. Adding a row here is a deliberate act with a
# readable diff; that is the intended cost.
_scout_hook_vocabulary() {
  cat <<'VOCAB'
husky
lefthook
pre-commit
lint-staged
commitlint
gitleaks
semgrep
trufflehog
shellcheck
shfmt
npx
npm
pnpm
yarn
bun
node
deno
tsc
eslint
prettier
jest
vitest
mocha
python
python3
pytest
pip
poetry
uv
black
ruff
mypy
flake8
isort
cargo
clippy
rustfmt
go
gofmt
golangci-lint
make
gradle
mvn
dotnet
php
composer
bundle
rspec
rubocop
swiftlint
ktlint
detekt
clang-format
terraform
tflint
docker
VOCAB
}

# _scout_hook_description FILE — the §7.2 advisory description.
#
# Shallow and static by contract: it reads which recognised tools the file
# names, and draws no conclusion about control flow, conditions or exit codes.
_scout_hook_description() {
  local file="$1" tok found="" n=0
  [ -f "$file" ] || { printf ''; return 0; }
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if grep -qE "(^|[^A-Za-z0-9_.-])$tok([^A-Za-z0-9_.-]|$)" "$file" 2>/dev/null; then
      if [ -z "$found" ]; then found="$tok"; else found="$found, $tok"; fi
      n=$((n + 1))
    fi
  done <<VOCABIN
$(_scout_hook_vocabulary)
VOCABIN
  if [ "$n" -eq 0 ]; then
    printf 'Runs commands Scout does not recognise. Advisory only — read the file before replacing it.'
  else
    printf 'Invokes %s. Advisory only: a hook can do anything, and this names only the tools Scout recognises.' "$found"
  fi
}

# ── §7.4's detector rules ───────────────────────────────────────────────────
#
# All four are REPORT-ONLY and all four are heuristics over YAML text rather
# than a parse of the workflow graph — which is stated here rather than implied,
# because the operator answers keep-or-retire on the strength of these rows.
# Their failure direction is a false POSITIVE (a row to dismiss), never a false
# negative that quietly certifies a pipeline that undermines the gates.
#
# _scout_ci_rule_line RULE FILE — the first line number matching RULE, or empty.
_scout_ci_rule_line() {
  local rule="$1" file="$2" n=""
  case "$rule" in
    auto-merge)
      # Defeats "no merge on red", the framework's first house rule.
      n=$(grep -nE 'merge[[:space:]]+--auto|--auto-merge|enable-pull-request-automerge|automerge|auto_merge' "$file" 2>/dev/null | head -1 | cut -d: -f1)
      ;;
    deploy-around-the-release-lane)
      # A deploy reached by a BRANCH PUSH rather than a tag or a dispatch skips
      # the Phase 3->4 gate entirely: code reaches production without crossing
      # it. The presence of `tags:` or `workflow_dispatch` is treated as the
      # release lane being in play, which is deliberately generous.
      if grep -qiE '(^|[^a-z])deploy' "$file" 2>/dev/null \
         && grep -qE '^[[:space:]]*push:' "$file" 2>/dev/null \
         && grep -qE '^[[:space:]]*branches:' "$file" 2>/dev/null \
         && ! grep -qE '^[[:space:]]*tags:|workflow_dispatch' "$file" 2>/dev/null; then
        n=$(grep -nE '^[[:space:]]*push:' "$file" 2>/dev/null | head -1 | cut -d: -f1)
      fi
      ;;
    force-push-or-history-rewrite-in-ci)
      # Destroys the tamper-evidence the whole audit story rests on.
      n=$(grep -nE 'push[[:space:]]+(-f|--force|--force-with-lease)|filter-repo|filter-branch' "$file" 2>/dev/null | head -1 | cut -d: -f1)
      ;;
    check-skipping)
      # Turns a red gate green silently — the exact defect class this
      # repository's own [WARN] trap embodies.
      n=$(grep -nE '^[[:space:]]*continue-on-error:[[:space:]]*true|^[[:space:]]*if:[[:space:]]*(\$\{\{[[:space:]]*)?always\(\)' "$file" 2>/dev/null | head -1 | cut -d: -f1)
      ;;
  esac
  printf '%s' "$n"
}

# _scout_ci_rule_why RULE — the fixed sentence for one rule. Fixed, because a
# generated explanation would be an invitation to interpolate file content.
_scout_ci_rule_why() {
  case "$1" in
    auto-merge)      printf 'Merges without depending on a required check, which defeats "no merge on red".' ;;
    deploy-around-the-release-lane)
                     printf 'A deploy triggered by a branch push rather than a tag or a dispatch reaches production without crossing the release gate.' ;;
    force-push-or-history-rewrite-in-ci)
                     printf 'Rewriting history from CI destroys the tamper-evidence the audit trail depends on.' ;;
    check-skipping)  printf 'A security or test step that cannot fail the run turns a red gate green silently.' ;;
    *)               printf '' ;;
  esac
}

# _scout_ci_files ROOT — the pipeline files present, relative, one per line.
_scout_ci_files() {
  local root="$1" f
  for f in "$root/.github/workflows"/*.yml "$root/.github/workflows"/*.yaml; do
    [ -f "$f" ] && printf '%s\n' "${f#$root/}"
  done
  for f in .gitlab-ci.yml bitbucket-pipelines.yml azure-pipelines.yml Jenkinsfile .circleci/config.yml; do
    [ -f "$root/$f" ] && printf '%s\n' "$f"
  done
  return 0
}

# scout_collisions_scan ROOT WORK — fills WORK with the collisions data.
#
# Writes:
#   colentries  `<path>\t<class>\t<bucket>\t<description>\t<note>\t<findings>`
#   coldetail   `<rule>\t<path>\t<line>\t<why>`
scout_collisions_scan() {
  local root="$1" work="$2" f n rules line why nsamples desc hookbase
  : > "$work/colentries"
  : > "$work/coldetail"

  # ── AI-layer surfaces: archive-and-replace (§7.1) ─────────────────────────
  [ -f "$root/.claude/settings.json" ] && _scout_col_add "$work" \
    ".claude/settings.json" "ai-settings" "archive-and-replace" "" \
    "The scaffolder OVERWRITES this file, then merges its own hook registrations into its own output — theirs is not consulted." ""
  [ -f "$root/.claude/settings.local.json" ] && _scout_col_add "$work" \
    ".claude/settings.local.json" "ai-settings-local" "archive-and-replace" "" \
    "OVERWRITTEN today. This is the conventional home for a developer's personal MCP roster and it is UNTRACKED, so the loss is not recoverable from git." ""
  [ -f "$root/.mcp.json" ] && _scout_col_add "$work" \
    ".mcp.json" "mcp" "archive-and-replace" "" \
    "Their MCP connections. Archived and restorable; re-adds are permitted and recorded." ""
  for f in session-handoff sweep-triage zoom-out grill-with-docs; do
    [ -f "$root/.claude/skills/$f/SKILL.md" ] && _scout_col_add "$work" \
      ".claude/skills/$f/SKILL.md" "skill" "archive-and-replace" "" \
      "A same-named skill is clobbered by an unguarded copy." ""
  done
  [ -f "$root/.claude/phase-state.json" ] && _scout_col_add "$work" \
    ".claude/phase-state.json" "framework-state" "archive-and-replace" "" \
    "Framework state that the scaffolder rewrites wholesale." ""
  if [ -d "$root/.claude-backup" ]; then
    _scout_col_add "$work" ".claude-backup/" "backup-dir" "archive-and-replace" "" \
      "The scaffolder REMOVES this directory outright, on a justification that only holds for a brand-new project. On an existing one it is the vendored framework's pre-merge backup of .claude/ — the operator's own work." ""
  fi

  # ── Git hooks (§7.1: archive-and-replace, except where the framework
  #    already composes politely) ──────────────────────────────────────────
  if [ -d "$root/.git/hooks" ]; then
    if [ -f "$root/.git/hooks/pre-commit" ]; then
      desc=$(_scout_hook_description "$root/.git/hooks/pre-commit")
      _scout_col_add "$work" ".git/hooks/pre-commit" "git-hook" "archive-and-replace" \
        "$desc" \
        "OVERWRITTEN today, unguarded. Husky, lefthook, pre-commit-framework and hand-rolled hooks are all destroyed." ""
    fi
    if [ -f "$root/.git/hooks/commit-msg" ]; then
      desc=$(_scout_hook_description "$root/.git/hooks/commit-msg")
      _scout_col_add "$work" ".git/hooks/commit-msg" "git-hook" "marker-composed" \
        "$desc" \
        "The framework already composes here: a marker-fenced append, idempotent. Their hook keeps running." ""
    fi
    for f in "$root/.git/hooks"/*; do
      [ -f "$f" ] || continue
      hookbase="${f##*/}"
      case "$hookbase" in
        *.sample|pre-commit|commit-msg) continue ;;
      esac
      desc=$(_scout_hook_description "$f")
      _scout_col_add "$work" ".git/hooks/$hookbase" "git-hook" "archive-and-replace" \
        "$desc" "Their hook. Archived with a restore line before the framework's set is installed." ""
    done
    nsamples=$(ls -1 "$root/.git/hooks"/*.sample 2>/dev/null | grep -c '')
    case "$nsamples" in ''|*[!0-9]*) nsamples=0 ;; esac
    if [ "$nsamples" -gt 0 ]; then
      _scout_col_add "$work" ".git/hooks/*.sample" "git-hook-sample" "archive-and-replace" \
        "" "$nsamples sample hooks git wrote at init. The scaffolder DELETES them (rm -f) so it does not misdetect the tree as an existing project." ""
    fi
  fi

  # ── Their pipelines: audit-only, never touched (§7.4) ────────────────────
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rules=""
    for r in auto-merge deploy-around-the-release-lane force-push-or-history-rewrite-in-ci check-skipping; do
      line=$(_scout_ci_rule_line "$r" "$root/$f")
      [ -n "$line" ] || continue
      why=$(_scout_ci_rule_why "$r")
      printf '%s\t%s\t%s\t%s\n' "$r" "$f" "$line" "$why" >> "$work/coldetail"
      if [ -z "$rules" ]; then rules="$r"; else rules="$rules,$r"; fi
    done
    _scout_col_add "$work" "$f" "ci" "audit-only" "" \
      "Never archived, never touched. The framework installs its gates as its own files so a working pipeline is not taken offline on day one." "$rules"
  done <<CIIN
$(_scout_ci_files "$root")
CIIN

  # ── Project files: keep theirs (§7.5) ────────────────────────────────────
  for f in FEATURES.md CHANGELOG.md BUGS.md RELEASE_NOTES.md; do
    [ -f "$root/$f" ] && _scout_col_add "$work" "$f" "project-doc" "keep-theirs" "" \
      "OVERWRITTEN from a template today. Under adoption it is treated as theirs: kept, and reconciled by the interview." ""
  done
  for f in CLAUDE.md PROJECT_INTAKE.md; do
    [ -f "$root/$f" ] && _scout_col_add "$work" "$f" "framework-doc" "keep-theirs" "" \
      "Notice-only when present: no sidecar, no backup copy, no template overwrite. Adoption creates these only when they are absent." ""
  done
  if [ -f "$root/.gitignore" ]; then
    _scout_col_add "$work" ".gitignore" "project-file" "marker-composed" "" \
      "Replaced by a template copy today, and their rules are lost. §7.1 names no row for .gitignore; the composing-writer precedent (a marker-fenced append) is what this report proposes, and an operator can disagree with it here rather than discover it afterwards." ""
  fi

  # ── Uncommitted work (§1.2's last row) ───────────────────────────────────
  # `--no-optional-locks` is load-bearing: a plain `git status` refreshes and
  # REWRITES `.git/index`, which would make a read-only scanner write to the
  # operator's repository on every run. The suite's R1 tree hash is what keeps
  # this flag here.
  if command -v git >/dev/null 2>&1 \
     && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    n=$(git --no-optional-locks -C "$root" status --porcelain 2>/dev/null | grep -c '')
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -gt 0 ]; then
      _scout_col_add "$work" "(uncommitted working tree)" "working-tree" "audit-only" "" \
        "$n path(s) are uncommitted. The scaffolder sweeps existing uncommitted work into a 'chore: initialize' commit WITH VERIFICATION BYPASSED. Commit or stash it yourself first — Scout will not touch it." ""
    fi
  fi
  return 0
}
