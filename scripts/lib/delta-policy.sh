#!/usr/bin/env bash
# scripts/lib/delta-policy.sh — read `.claude/delta-policy.json`, the delta
# module's PROJECT-OWNED policy file, with per-key fallback to the framework
# defaults.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §7.2 (the schema — the
# defaults below are that JSON verbatim), §3.2 (the mechanism/policy split and
# the DECIDED sync semantics: NOTICE-ONLY, modelled on the `# BL-099-DOC-GUARD`
# rendered-doc fence), §3.1 (this file is a member of the severable delta
# module's inventory).
#
# (No `# BL-NNN-…` marker on purpose — no backlog entry exists for the delta
# build, and minting one would red scripts/lint-bl-markers.sh, whose first pass
# resolves every marker to a `## BL-NNN:` entry. The design-doc path above is
# the citation. Same reasoning as scripts/lib/delta-state.sh and
# scripts/lint-delta-boundary.sh.)
#
# ROLE — and the one thing it must never do
#   MECHANISM lives here and ships with the framework, refreshed by
#   `scripts/upgrade-project.sh` like any other script. POLICY lives in
#   `.claude/delta-policy.json` and belongs to the project. After birth, NOTHING
#   in the framework rewrites that file — not an upgrade, not a re-seed, not a
#   "repair". §3.2 weighed the managed-region model (the `hook-templates.sh`
#   `SOIF_*_OPEN/_CLOSE` pattern) and the sidecar `.new` model and REJECTED
#   both: a project's tuned gate floor being silently reverted is the exact
#   failure the mechanism/policy split exists to prevent.
#
#   The cost of that decision is that an old file can drift below a new
#   framework default and nobody notices. Two things pay it, both here:
#     • PER-KEY FALLBACK AT READ TIME (delta_policy_get) — an absent key is not
#       an error and not an empty string, it is the framework default. An old
#       policy file is therefore never BROKEN by a newer framework, merely
#       quiet.
#     • THE NOTICE (delta_policy_notice) — one line, naming the keys the
#       framework has learned that this file lacks, applying nothing.
#
# WHY A CORRUPT FILE IS NOT AN ERROR
#   Reads FAIL TOWARD THE DEFAULTS with a visible warning on stderr and rc 0.
#   The alternative — crashing every caller — turns one bad edit of a
#   project-owned file into a dead toolchain, and the repair (rewriting it) is
#   exactly the thing §3.2 forbids. The file is never repaired, replaced or
#   deleted here.
#
# DEPENDENCY DIRECTION (D1)
#   delta -> core is allowed. core -> delta is forbidden and lint-enforced by
#   scripts/lint-delta-boundary.sh, with ONE allowlisted seam
#   (scripts/process-checklist.sh). Nothing in this file may be sourced by a
#   core script.
#
# BASH 3.2 COMPATIBILITY
#   macOS ships bash 3.2.57. No associative arrays, no ${var,,}, no `((x++))`.
#   Every function is errexit-safe: this lib is sourced into
#   scripts/process-checklist.sh, which runs under `set -euo pipefail`.

# delta_policy_path [project_root]
#   Echo the path of the policy file for a project root (default: cwd). Pure;
#   creates nothing.
delta_policy_path() {
  local root="${1:-.}" p
  p="${root%/}/.claude/delta-policy.json"
  # See scripts/lib/delta-state.sh::delta_state_path — a `.`-rooted call would
  # render every diagnostic (including the operator-facing upgrade notice) as
  # `./.claude/…`. Both spellings resolve to the same file.
  case "$p" in ./*) p="${p#./}" ;; esac
  printf '%s\n' "$p"
}

# delta_policy_defaults
#   The §7.2 framework defaults, verbatim. THIS IS THE SCHEMA — do not add,
#   rename or reinterpret a key here without amending the design.
#
#   Two things the JSON does not make obvious (§7.2, R-DT-7):
#     • `hotfix` carries no `close_review` token because `retro_review` IS the
#       close review, arriving late and collateralised by the §9.2 release
#       refusal. Adding `close_review` to that row would either double-charge
#       the review or let a hotfix satisfy it at ship time and make the retro
#       optional — the loan going unrepaid.
#     • `touch_trigger` maps to ONE token because `threat_model_refresh`
#       bundles both halves (a threat-model update AND a scoped scanner
#       re-run). They are never independently completable.
#   And two more, from the §7.2 prose:
#     • TWO SLA tables on purpose (C4): `fix_sla` mirrors
#       templates/project-intake.md's SEV defaults; `cvss_sla` mirrors
#       docs/governance-framework.md's CVSS-keyed table, because a CVE arrives
#       with a CVSS score and not a SEV. Neither has an enforced home in the
#       tree today, which is why both live here.
#     • `risk_surfaces` ships EMPTY on purpose. A framework-guessed default
#       would be wrong for most projects and would look authoritative. The
#       first `delta.sh --open` prompts for it.
delta_policy_defaults() {
  cat <<'DELTA_POLICY_DEFAULTS_EOF'
{
  "schemaVersion": 1,
  "classes": {
    "feature":        { "gates": ["brief", "brief_review", "ledger_row", "build_loop", "close_review", "changelog"] },
    "fix":            { "gates": ["ledger_row", "repro_test_red_first", "close_review", "changelog"] },
    "hotfix":         { "gates": ["ledger_row", "audit_row_at_open", "retro_review", "changelog"], "retro_due_days": 3 },
    "security-patch": { "gates": ["ledger_row", "repro_test_red_first", "dependency_scan", "sbom_refresh", "flagged_release_note", "close_review", "changelog"] }
  },
  "attribute_toggles": {
    "risk_core":       ["brief_review"],
    "level_evolution": ["brief"],
    "touch_trigger":   ["threat_model_refresh"]
  },
  "risk_surfaces": [],
  "size_thresholds": { "small": 50, "significant": 400 },
  "cadence": { "routine_review_days": 14, "deep_security_days": 95 },
  "fix_sla": { "SEV-1": "24h", "SEV-2": "7d", "SEV-3": "best-effort", "SEV-4": "post-mvp" },
  "cvss_sla": { "critical": "24h", "high": "7d", "medium": "next-monthly", "low": "next-quarterly" },
  "semver": { "feature": "minor", "fix": "patch", "hotfix": "patch", "security-patch": "patch", "breaking": "major" }
}
DELTA_POLICY_DEFAULTS_EOF
}

# _delta_policy_project_doc [project_root]
#   Echo the project's policy document as compact JSON, or the literal `null`
#   when it is absent or unparseable (warning on stderr in the latter case).
#   `null` is the right sentinel because every consumer below already treats a
#   null lookup as "fall back to the default" — one code path, not two.
_delta_policy_project_doc() {
  local root="${1:-.}" f
  f="$(delta_policy_path "$root")"
  if [ ! -f "$f" ]; then
    printf '%s\n' "null"
    return 0
  fi
  if ! jq -e . "$f" >/dev/null 2>&1; then
    printf '%s\n' "delta-policy: $f is not valid JSON — every key is resolving to its framework default. The file was NOT modified, repaired or replaced; it is project-owned, so fix it yourself." >&2
    printf '%s\n' "null"
    return 0
  fi
  jq -c . "$f"
}

# delta_policy_get <project_root> <dotted.key>
#   Per-key read with fallback. Prints the resolved value and returns 0; prints
#   NOTHING and returns 1 when the key exists in neither the project file nor
#   the framework defaults, so a caller can tell "absent, defaulted" from "no
#   such policy key". Scalars print raw; objects and arrays print as compact
#   JSON.
#
#   Resolution order is per KEY, not per FILE: the project's own value wins if
#   it is present, otherwise the framework default — evaluated at every read,
#   at every depth. A file that carries `size_thresholds.small` but not
#   `size_thresholds.significant` keeps its tuned `small` AND gets the default
#   `significant`; nothing has to be migrated for that to work.
delta_policy_get() {
  local root="${1:-.}" key="${2:-}"
  if [ -z "$key" ]; then
    printf '%s\n' "delta_policy_get: a policy key is required (dot-separated, e.g. size_thresholds.small)" >&2
    return 2
  fi
  local defaults proj out
  defaults="$(delta_policy_defaults)"
  proj="$(_delta_policy_project_doc "$root")"
  if ! out="$(jq -r -n --argjson d "$defaults" --argjson p "$proj" --arg k "$key" '
      ($k | split(".")) as $path
    | (try ($p | getpath($path)) catch null) as $pv
    | (if $pv == null then (try ($d | getpath($path)) catch null) else $pv end) as $v   # DELTA-POLICY-FALLBACK
    | if $v == null then "-"
      else "+" + (if (($v | type) == "object") or (($v | type) == "array") then ($v | tojson) else ($v | tostring) end)
      end
  ' 2>/dev/null)"; then
    printf '%s\n' "delta-policy: could not resolve key '$key'" >&2
    return 1
  fi
  case "$out" in
    '-') return 1 ;;
    '+'*) printf '%s\n' "${out#+}"; return 0 ;;
    *) return 1 ;;
  esac
}

# delta_policy_seed <project_root>
#   THE SEED WRITER — the one and only time the framework writes this file.
#   Called once at first use (delta open, in a later WP; reachable today via the
#   seam's --delta-policy-init). Writing is atomic (tmp+mv in the same
#   directory) for the same reason the state file's is.
#
#   BIRTH-ONCE. An existing file is left completely alone — not merged, not
#   topped up with new keys, not backed up. That is §3.2's decision and it is
#   what the notice arm exists to compensate for. Returning 0 on the no-op is
#   deliberate: "the file is already there" is a success, and a caller that had
#   to distinguish it would be tempted to "fix" it.
delta_policy_seed() {
  local root="${1:-.}" f dir
  f="$(delta_policy_path "$root")"
  if [ -f "$f" ]; then return 0; fi          # DELTA-POLICY-BIRTHONCE
  dir="${f%/*}"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" || return 1
  fi
  local target="$f.tmp"
  rm -f "$target" 2>/dev/null || true
  if ! delta_policy_defaults | jq . > "$target" 2>/dev/null; then
    rm -f "$target" 2>/dev/null || true
    printf '%s\n' "delta-policy: could not render the framework defaults — $f was NOT created." >&2
    return 1
  fi
  mv "$target" "$f" || { rm -f "$target" 2>/dev/null || true; return 1; }
  printf '%s\n' "delta-policy: seeded $f with the framework defaults. This file is PROJECT-OWNED from now on — the framework will never rewrite it."
  return 0
}

# delta_policy_missing_keys <project_root>
#   One dotted key per line: every path present in the framework defaults and
#   ABSENT from the project file. Returns 1 (and prints nothing) when there is
#   no file to compare against, or when the file cannot be parsed.
#
#   SHALLOWEST-PATH reporting: if `classes` is missing entirely the answer is
#   `classes`, not four separate `classes.<name>.gates` rows. A project that has
#   a `classes` object but no `hotfix` entry gets `classes.hotfix`. That keeps
#   the notice one readable line in the common cases and still pinpoints a
#   nested gap.
#
#   A key the project explicitly set to `null` reads as missing. That matches
#   delta_policy_get's resolution exactly — a null value already falls back to
#   the default — so the notice never disagrees with the reader.
delta_policy_missing_keys() {
  local root="${1:-.}" f proj defaults
  f="$(delta_policy_path "$root")"
  [ -f "$f" ] || return 1
  proj="$(_delta_policy_project_doc "$root")"
  if [ -z "$proj" ] || [ "$proj" = "null" ]; then return 1; fi
  defaults="$(delta_policy_defaults)"
  jq -r -n --argjson d "$defaults" --argjson p "$proj" '
    def miss($dv; $pv; $pre):
      if $pv == null then [$pre]
      elif (($dv | type) == "object") and (($pv | type) == "object") then
        ($dv | keys_unsorted) | map(. as $k | miss($dv[$k]; $pv[$k]; ($pre + "." + $k))) | add // []
      else [] end;
    ($d | keys_unsorted) | map(. as $k | miss($d[$k]; $p[$k]; $k)) | add // []
    | .[]
  ' 2>/dev/null
}

# delta_policy_notice <project_root>
#   The NOTICE-ONLY arm (§3.2). Prints ONE line naming the framework policy keys
#   this project's file lacks — and writes nothing, anywhere, ever. Silent (rc 0)
#   when there is no policy file (a project that never opened a delta gets no
#   noise), when the file cannot be parsed (the reader already warned), and when
#   nothing is missing.
#
#   This function is what `scripts/upgrade-project.sh` reaches through the seam.
#   It deliberately has no flag, no mode and no apply path: there is nothing to
#   consent to, because there is nothing it could write.
delta_policy_notice() {
  local root="${1:-.}" f keys joined
  f="$(delta_policy_path "$root")"
  [ -f "$f" ] || return 0
  keys="$(delta_policy_missing_keys "$root")" || return 0
  [ -n "$keys" ] || return 0
  joined="$(printf '%s' "$keys" | tr '\n' ' ' | sed -e 's/  */, /g' -e 's/, $//')"
  printf '%s\n' "[NOTICE] $f is project-owned and was NOT modified. Framework policy key(s) absent from it: ${joined}. Absent keys already resolve to the framework default at read time — add them yourself only if you want to pin different values."
  return 0
}
