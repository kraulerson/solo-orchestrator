#!/usr/bin/env bash
# scripts/lib/currency-manifest.sh
#
# BL-109 SLICE-S1 (Layer 0 — Inventory). Writer/reader helpers for the ONE
# versioned `currency` block that lives INSIDE the existing
# `.claude/manifest.json`. There is NEVER a second, separate manifest file — the
# dual-source ban is the design's review-r1 B2 finding (acceptance: a repo-wide
# grep for the rejected standalone-manifest filename stays 0 in product code).
# The pins already in this file (soloFrameworkCommit / frameworkCommit /
# frameworkVersion) are untouched; this block sits BESIDE them.
#
# Schema (design v1.1 §2-L0, exactly):
#   currency: {
#     schemaVersion: 1,
#     soloFrameworkPath,                      # init.sh's own $SCRIPT_DIR
#     files: { path -> { sha256, mode, class, state } },
#     renderBases: {                          # captured AT the render site
#       A1: { artifact -> { templateSha, outputSha } },   # script-rendered
#       A2: { artifact -> { templateSha } }               # agent-authored
#     },
#     # An adopted project (`## BL-337:`, design §2-L0 amendment 2026-11-02):
#     # no render site captured a base, so every row is the UNKNOWN shape —
#     #   A1: { artifact -> { templateSha: null, outputSha: null, base: "unknown", reason } }
#     #   A2: { artifact -> { templateSha: null, base: "unknown", reason } }
#     # — and no A1 artifact has a files{} row.
#     hooks: { name -> present | absent-intentional | absent-unavailable },
#     mcpProbe: { context7: present | absent }
#   }
#
# files{} is derived MECHANICALLY from the same source as
# scripts/lib/scaffold-shipped-set.sh (extended there to reference docs + skills)
# — NEVER a hand-maintained list. Class assignment:
#   M — scripts (incl. hooks-related libs) + vendored skills
#   T — the docs/reference verbatim set
#   A1 — CLAUDE.md + PROJECT_INTAKE.md (the two script-rendered artifacts)
# A2 artifacts (PRODUCT_MANIFESTO.md, PROJECT_BIBLE.md) do NOT exist at birth
# (created by no script — review-r1 B3a); they appear only under renderBases.A2
# by template sha.
#
# jq-availability / failure handling mirrors init.sh's soloFrameworkCommit
# birth-stamp: jq is assumed present at the stamp site (the manifest itself is
# jq-built); the final write is the same `jq ... > tmp && mv tmp manifest`
# atomic-rename pattern. If jq is somehow absent, the stamp is a no-op (the
# manifest keeps its pre-block bytes).
#
# bash-3.2 safe: no associative arrays, no `[[ -v ]]`, no `((x++))` under set -e,
# no process-substitution requirement. Pure helpers — the only writes are the
# render-base scratch file (a $TMPDIR temp) and the final atomic manifest merge.

# ── Dependency wiring ────────────────────────────────────────────────────────
# scaffold-shipped-set.sh provides the mechanical shipped-set parsers; source it
# from our own directory if a caller has not already. hook-templates.sh is
# sourced for its region-body emitters/markers (the hook-enum predicate no
# longer consults soif_lang_test_pattern — BL-107 installs universally).
_soif_cm_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v soif_parse_shipped_scripts >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  [ -f "$_soif_cm_dir/scaffold-shipped-set.sh" ] && . "$_soif_cm_dir/scaffold-shipped-set.sh"
fi
if ! command -v soif_lang_test_pattern >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  [ -f "$_soif_cm_dir/hook-templates.sh" ] && . "$_soif_cm_dir/hook-templates.sh"
fi
unset _soif_cm_dir

# ── Primitives: sha256 + mode ────────────────────────────────────────────────
# soif_currency_sha256 <file> — hex sha256, rc 1 on a missing file.
# shasum first, then sha256sum (`# BL-337-SHA256-FALLBACK`): Fedora's
# `dnf install git jq` brings no shasum, and on such a host every files{} row
# was skipped, so adoption's receipt refused the run. Probed, not chained with
# `||`, for the reason adopt_sha256 gives: the pipeline's status is awk's, and
# awk succeeds on empty input. Neither tool is rc 1 with a message, never an
# empty hash that reads as success.
soif_currency_sha256() {
  local f="$1"
  [ -f "$f" ] || return 1
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then   # BL-337-SHA256-FALLBACK
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  else
    printf 'soif_currency_sha256: neither shasum nor sha256sum is on PATH; cannot hash %s\n' "$f" >&2
    return 1
  fi
}

# soif_currency_mode <file> — octal permission bits, GNU-first then BSD.
soif_currency_mode() {
  local f="$1"
  [ -e "$f" ] || return 1
  stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null
}

# ── Hook three-state enum (review-r1 M9) ─────────────────────────────────────
# soif_currency_hook_state <hook-name> <language> — reproduces init.sh's own
# install decision mechanically:
#   commit-msg: PRESENT for every language (BL-107-UNIVERSAL-INSTALL). Before
#     BL-107, init.sh installed the BL-072 TDD gate only when
#     soif_lang_test_pattern was non-empty, and this predicate mirrored the
#     skip as absent-intentional (rust) / absent-unavailable (`other`). Those
#     enum values remain VALID FOR READERS — manifests written by pre-BL-107
#     scaffolds still carry them, and freshness-detect keeps surfacing
#     absent-unavailable at the enforcement tier (citing BL-107) so a legacy
#     project's missing gate is a finding, not a fact. New manifests record
#     present.
#   pre-commit: init.sh installs the fallback pre-commit hook UNCONDITIONALLY
#     (language-agnostic gitleaks + Semgrep), so it is always present at birth.
soif_currency_hook_state() {
  local hook="$1" language="$2"
  case "$hook" in
    pre-commit)
      printf '%s' "present" ;;
    commit-msg)
      # BL-107-UNIVERSAL-INSTALL: the gate ships for every language.
      printf '%s' "present" ;;
    *)
      printf '%s' "absent-unavailable" ;;
  esac
}

# ── MCP presence probe ───────────────────────────────────────────────────────
# soif_currency_mcp_probe — emits {"context7": "present"|"absent"} using the
# EXISTING is_context7_mcp_registered helper (reuse, never reimplement). Honest
# best-effort: if the helper is not sourced or jq is missing it reports absent.
soif_currency_mcp_probe() {
  local state="absent"
  if command -v is_context7_mcp_registered >/dev/null 2>&1; then
    if is_context7_mcp_registered >/dev/null 2>&1; then
      state="present"
    fi
  fi
  jq -n --arg s "$state" '{context7: $s}'
}

# ── Render-base capture (called AT the render site) ──────────────────────────
# The render bases are captured immediately at the init.sh render sites and
# stashed in a scratch file ($SOIF_CURRENCY_RENDERBASE_FILE) so the stamp can
# read them WITHOUT re-hashing a possibly-already-touched artifact post-hoc
# (post-hoc hashing is a MAJOR per the verify focus). Each line is TSV:
#   <group>\t<artifact>\t<templateSha>\t<outputSha>\t<outputMode>
# group A1 records template+output; group A2 records template only (output cols
# empty). For A1, files{} reuses the captured output sha/mode verbatim, so no A1
# artifact is ever hashed twice.

# soif_currency_renderbase_init — start a fresh render-base scratch file and
# export its path. Called once by init.sh before the first render.
soif_currency_renderbase_init() {
  SOIF_CURRENCY_RENDERBASE_FILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/soif-currency-rb.$$")"
  : > "$SOIF_CURRENCY_RENDERBASE_FILE"
  export SOIF_CURRENCY_RENDERBASE_FILE
}

# soif_currency_record_render_base <group> <artifact> <template-file> <output-file|"">
soif_currency_record_render_base() {
  local group="$1" artifact="$2" template="$3" output="$4"
  local store="${SOIF_CURRENCY_RENDERBASE_FILE:-}"
  [ -n "$store" ] || return 0
  local tsha="" osha="" omode=""
  tsha="$(soif_currency_sha256 "$template" 2>/dev/null)" || tsha=""
  if [ -n "$output" ]; then
    osha="$(soif_currency_sha256 "$output" 2>/dev/null)" || osha=""
    omode="$(soif_currency_mode "$output" 2>/dev/null)" || omode=""
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$group" "$artifact" "$tsha" "$osha" "$omode" >> "$store"
}

# ── files{} rows (M/T from the shipped-set parsers) ──────────────────────────
# _soif_currency_mt_prefixed <class> <list> — the list's non-empty lines, each
# prefixed "<class>\t". awk's own status is the answer: busybox awk refuses a
# bare `length` pattern and exits 1, and an ignored status there turned a parse
# failure into rc 0 with no M/T rows at all. `length($0) > 0`, never bare `length`.
_soif_currency_mt_prefixed() {
  local rc=0
  printf '%s\n' "$2" | awk -v c="$1" 'length($0) > 0 { print c "\t" $0 }' \
    || { rc=$?; printf '_soif_currency_mt_files_tsv: awk failed (rc %s) building the candidate list\n' "$rc" >&2; return 1; }
}

# _soif_currency_mt_files_tsv <init_file> <framework_dir> <project_dir>
#   Emits M (scripts + skills) and T (reference docs + bulk project templates)
#   rows, MECHANICALLY derived: one TSV row "<rel>\t<sha>\t<mode>\t<class>\tcurrent"
#   per file, hashed from the SCAFFOLDED project tree (what the project actually
#   holds), in parser order. A rel path missing from the tree is skipped (a real
#   gap the aggregator fidelity test is designed to catch).
#
#   BL-109 S3, carried obligation 2: the bulk `templates/generated/*.tmpl`
#   skeletons init.sh ships verbatim are Class T (soif_parse_shipped_templates),
#   joining the docs/reference verbatim set. Render-source templates (claude-md,
#   project-bible, product-manifesto) are excluded there and stay renderBases-only.
#
#   ONE hasher and one stat for every file (`# BL-337-BATCH-HASH`; two stats on
#   BSD, where GNU's -c fails first). Three processes per file cost ~1.2 s a
#   block over an adopted project, and adoption builds the block twice
#   (rehearsal + real). Hashes pair with files by argument order, and
#   that is safe only because the hasher exited 0 (it read every file, so none is
#   missing a line) and returned exactly one line per file (so no name broke a
#   line in two — macOS's sha256sum does not escape a newline). Anything else is
#   rc 1 with a message, never a row. Each line's first field is kept verbatim —
#   with the `\` shasum prefixes when a path holds a backslash — so the row is
#   what soif_currency_sha256 gives that same path (byte-identical to the per-file
#   build). That is NOT what the readers compare with: init.sh stamps with the
#   project dir ".", so its rows are plain hex, while the freshness check hashes
#   the absolute path, which carries the `\` when that path does (`## BL-363:`).
_soif_currency_mt_files_tsv() {
  local init_file="$1" fw_dir="$2" proj_dir="$3"
  local scripts_list="" skills_list="" docs_list="" templates_list=""
  local tab="" rel="" cls="" hashes="" modes="" tool="" h="" i=0 n=0 k=0 cands="" part="" abs_dir=""
  local rels=() clss=() paths=() shas=() mds=()
  scripts_list="$(soif_parse_shipped_scripts "$init_file" "$fw_dir/scripts" 2>/dev/null)"
  skills_list="$(soif_parse_shipped_skills "$init_file" "$fw_dir/templates/generated/skills" 2>/dev/null)"
  docs_list="$(soif_parse_shipped_reference_docs "$init_file" 2>/dev/null)"
  templates_list="$(soif_parse_shipped_templates "$init_file" 2>/dev/null)"
  tab="$(printf '\t')"
  part="$(_soif_currency_mt_prefixed M "$scripts_list")" || return 1; cands="$part"
  part="$(_soif_currency_mt_prefixed M "$skills_list")" || return 1; cands="$cands
$part"
  part="$(_soif_currency_mt_prefixed T "$docs_list")" || return 1; cands="$cands
$part"
  part="$(_soif_currency_mt_prefixed T "$templates_list")" || return 1; cands="$cands
$part"
  while IFS="$tab" read -r cls rel; do
    [ -n "$rel" ] && [ -f "$proj_dir/$rel" ] || continue
    rels[$n]="$rel"; clss[$n]="$cls"; paths[$n]="$proj_dir/$rel"; n=$((n + 1))
  done <<CANDIDATES
$cands
CANDIDATES
  [ "$n" -gt 0 ] || return 0

  # shasum first, then sha256sum (`# BL-337-SHA256-FALLBACK`), as soif_currency_sha256.
  if command -v shasum >/dev/null 2>&1; then
    tool="shasum"; hashes="$(shasum -a 256 "${paths[@]}")"
  elif command -v sha256sum >/dev/null 2>&1; then   # BL-337-SHA256-FALLBACK
    tool="sha256sum"; hashes="$(sha256sum "${paths[@]}")"
  else
    abs_dir="$(cd "$proj_dir" && pwd)" || abs_dir="$proj_dir"   # init.sh stamps with "."
    printf '_soif_currency_mt_files_tsv: neither shasum nor sha256sum is on PATH; cannot hash %s file(s) under %s; install shasum (perl) or sha256sum (coreutils)\n' "$n" "$abs_dir" >&2
    return 1
  fi || { printf '_soif_currency_mt_files_tsv: %s failed hashing %s file(s) under %s\n' "$tool" "$n" "$proj_dir" >&2; return 1; }
  modes="$(stat -c '%a' "${paths[@]}" 2>/dev/null)" || modes="$(stat -f '%Lp' "${paths[@]}" 2>/dev/null)" || modes=""

  k=0
  while IFS= read -r h; do shas[$k]="${h%% *}"; k=$((k + 1)); done <<HASHES
$hashes
HASHES
  [ "$k" -eq "$n" ] || { printf '_soif_currency_mt_files_tsv: %s gave %s hash line(s) for %s file(s); refusing to pair them\n' "$tool" "$k" "$n" >&2; return 1; }   # BL-337-BATCH-HASH
  k=0
  while IFS= read -r h; do mds[$k]="$h"; k=$((k + 1)); done <<MODES
$modes
MODES
  [ "$k" -eq "$n" ] || { printf '_soif_currency_mt_files_tsv: stat gave %s mode line(s) for %s file(s); refusing to pair them\n' "$k" "$n" >&2; return 1; }

  i=0
  while [ "$i" -lt "$n" ]; do
    h="${shas[$i]#\\}"
    case "$h" in *[!0123456789abcdef]*) h="" ;; esac
    [ "${#h}" -eq 64 ] || { printf '_soif_currency_mt_files_tsv: %s gave "%s" for %s, which is not a sha256\n' "$tool" "${shas[$i]}" "${paths[$i]}" >&2; return 1; }
    printf '%s\t%s\t%s\t%s\tcurrent\n' "${rels[$i]}" "${shas[$i]}" "${mds[$i]}" "${clss[$i]}"
    i=$((i + 1))
  done
}

# ── The stamp (writer) ───────────────────────────────────────────────────────
# soif_currency_block <init_file> <framework_dir> <project_dir> <language> \
#                     <solo_framework_path> [unknown:<reason>]
#   Prints the whole `currency` block as JSON. With no sixth argument the render
#   bases come from $SOIF_CURRENCY_RENDERBASE_FILE, captured at init.sh's render
#   sites — the birth stamp's own shape, unchanged.
#
#   `unknown:<reason>` (`## BL-337:`, Karl 2026-10-08) is for a birth with no
#   render step to capture from: adoption. Each A1/A2 artifact init.sh records
#   gets a row saying its base is UNKNOWN —
#     A1: { templateSha: null, outputSha: null, base: "unknown", reason }
#     A2: { templateSha: null, base: "unknown", reason }
#   — and NOT `{}` or a "" sha, which every reader takes as "nothing recorded"
#   and skips. `null` is no sha a template can have, and `base` names why it is
#   absent, so a reader cannot mistake the row for a base and must say so.
#   SYNC: the four artifacts are init.sh's four soif_currency_record_render_base
#   calls and freshness-detect.sh's `_soif_fresh_check_render_base` rows
#   (tests/test-bl337-adopt-currency-stamp.sh A3 derives them from init.sh).
#   No A1 files{} row is written then: an A1 row is the output captured AT the
#   render, and hashing the file afterwards is the post-hoc base this file's
#   render-base section rules out.
soif_currency_block() {
  local init_file="$1" fw_dir="$2" proj_dir="$3"
  local language="$4" solo_fw_path="$5" rb_mode="${6:-}"

  # M/T rows (scripts + skills + reference docs), hashed from the project tree.
  local mt_tsv
  mt_tsv="$(_soif_currency_mt_files_tsv "$init_file" "$fw_dir" "$proj_dir")" || return 1

  local a1_file_tsv="" a1_json="" a2_json=""
  case "$rb_mode" in
    "")
      # Render-base scratch → A1 file rows + A1/A2 renderBases objects.
      local store store_content=""
      store="${SOIF_CURRENCY_RENDERBASE_FILE:-}"
      if [ -n "$store" ] && [ -f "$store" ]; then
        store_content="$(cat "$store")"
      fi
      a1_file_tsv="$(printf '%s\n' "$store_content" \
        | awk -F'\t' 'NF>=5 && $1=="A1" { print $2"\t"$4"\t"$5"\tA1\tcurrent" }')"
      a1_json="$(printf '%s\n' "$store_content" \
        | awk -F'\t' 'NF>=4 && $1=="A1"' \
        | jq -Rn '[inputs | select(length>0) | split("\t") | {(.[1]): {templateSha: .[2], outputSha: .[3]}}] | add // {}')"
      a2_json="$(printf '%s\n' "$store_content" \
        | awk -F'\t' 'NF>=3 && $1=="A2"' \
        | jq -Rn '[inputs | select(length>0) | split("\t") | {(.[1]): {templateSha: .[2]}}] | add // {}')"
      ;;
    unknown:?*)
      local reason="${rb_mode#unknown:}"
      a1_json="$(jq -n --arg r "$reason" '{"CLAUDE.md": {templateSha: null, outputSha: null, base: "unknown", reason: $r},
        "PROJECT_INTAKE.md": {templateSha: null, outputSha: null, base: "unknown", reason: $r}}')"   # BL-337-RB-UNKNOWN
      a2_json="$(jq -n --arg r "$reason" '{"PROJECT_BIBLE.md": {templateSha: null, base: "unknown", reason: $r},
        "PRODUCT_MANIFESTO.md": {templateSha: null, base: "unknown", reason: $r}}')"
      ;;
    *)
      printf 'soif_currency_block: unknown render-base mode %s\n' "$rb_mode" >&2
      return 1 ;;
  esac

  # files{} = M/T rows + A1 rows, folded into one object.
  local all_tsv files_json
  all_tsv="$(printf '%s\n%s\n' "$mt_tsv" "$a1_file_tsv")"
  files_json="$(printf '%s\n' "$all_tsv" \
    | jq -Rn '[inputs | select(length>0) | split("\t") | {(.[0]): {sha256: .[1], mode: .[2], class: .[3], state: .[4]}}] | add // {}')"

  # hooks{} three-state enum + mcpProbe.
  local cm_state pc_state hooks_json mcp_json
  cm_state="$(soif_currency_hook_state commit-msg "$language")"
  pc_state="$(soif_currency_hook_state pre-commit "$language")"
  hooks_json="$(jq -n --arg cm "$cm_state" --arg pc "$pc_state" \
    '{"commit-msg": $cm, "pre-commit": $pc}')"
  mcp_json="$(soif_currency_mcp_probe)"

  # Assemble the block.
  jq -n \
    --argjson files "$files_json" \
    --argjson a1 "$a1_json" \
    --argjson a2 "$a2_json" \
    --argjson hooks "$hooks_json" \
    --argjson mcp "$mcp_json" \
    --arg path "$solo_fw_path" \
    '{schemaVersion: 1, soloFrameworkPath: $path, files: $files,
      renderBases: {A1: $a1, A2: $a2}, hooks: $hooks, mcpProbe: $mcp}'
}

# soif_currency_stamp <manifest> <init_file> <framework_dir> <project_dir> \
#                     <language> <solo_framework_path>
#   init.sh's birth stamp: soif_currency_block's captured shape, jq-merged into
#   <manifest> with the atomic-rename pattern. Additive: every pre-existing
#   manifest field is preserved. No-op if jq is unavailable. Adoption does not
#   call this; it merges soif_currency_block's unknown shape through its own
#   checked writer (adopt_write_currency).
soif_currency_stamp() {
  local manifest="$1" init_file="$2" fw_dir="$3" proj_dir="$4"
  local language="$5" solo_fw_path="$6"
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$manifest" ] || return 0

  local currency_json
  currency_json="$(soif_currency_block "$init_file" "$fw_dir" "$proj_dir" "$language" "$solo_fw_path")"

  # Merge — atomic rename, mirrors the soloFrameworkCommit stamp.
  jq --argjson currency "$currency_json" '.currency = $currency' \
    "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
}

# ── Readers ──────────────────────────────────────────────────────────────────
# soif_currency_read <manifest> <jq-filter> — thin jq -r reader over the block.
soif_currency_read() {
  jq -r "$2" "$1" 2>/dev/null
}

# soif_currency_file_field <manifest> <path> <field> — one files{} entry field
# (sha256|mode|class|state) for a tracked path; empty if absent.
soif_currency_file_field() {
  jq -r --arg p "$2" --arg f "$3" '.currency.files[$p][$f] // empty' "$1" 2>/dev/null
}
