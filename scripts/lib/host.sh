#!/usr/bin/env bash
# scripts/lib/host.sh — host dispatcher. Reads .claude/manifest.json for the
# `host` field and sources the matching driver in scripts/host-drivers/<host>.sh.
# Callers use the unified interface exposed by the sourced driver:
#   host_name, host_require_cli, host_create_repo, host_register_remote,
#   host_push_initial, host_configure_protection, host_verify_protection
#
# For host = "other", this file provides inline implementations (URL paste +
# manual attestation) instead of sourcing a driver file.

_host_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

host_read_from_manifest() {
  local manifest
  manifest="$(_host_repo_root)/.claude/manifest.json"
  if [ ! -f "$manifest" ]; then
    echo "host.sh: .claude/manifest.json not found at $manifest" >&2
    return 1
  fi
  local host
  host=$(jq -r '.host // empty' "$manifest" 2>/dev/null || true)
  if [ -z "$host" ]; then
    echo "host.sh: manifest.json missing 'host' field. Run: scripts/check-gate.sh --backfill-host" >&2
    return 2
  fi
  echo "$host"
}

# ── Pipeline paths ─────────────────────────────────────────────────────────
# host_pipeline_resolve [host] — the ONE place that knows where each host keeps
# its CI and release pipelines. Sets three globals:
#
#   HOST_CI_PATH          the root pipeline file the host actually executes
#   HOST_RELEASE_PATH     where the release steps live
#   HOST_RELEASE_EXECUTES how those steps reach the runner:
#                           file    — its own file, executed directly (GitHub)
#                           include — its own file, pulled in by the root
#                                     pipeline's `include:` (GitLab)
#                           import  — its own file, pulled in by the root
#                                     pipeline's `definitions.imports` plus an
#                                     `import:` reference (Bitbucket)
#
# `file` needs no wiring. `include` and `import` DO, and a release file nothing
# references never executes — which is the deepest form of this entry's defect
# and what a reader must check beyond `[ -f ]`.
#
# THE THIRD FIELD IS NOT DECORATION. Without it every caller re-derives
# "…but Bitbucket is different" locally, which is exactly the duplication that
# produced BL-229: five scripts each hardcoded `.github/workflows/release.yml`,
# so on GitLab and Bitbucket the readers either said nothing (check-phase-gate,
# a skipped block indistinguishable from a clean one) or said something false
# (validate.sh, `[FAIL] CI pipeline missing` on a healthy project).
#
# BITBUCKET DOES SUPPORT A SAME-REPO IMPORT, AND AN EARLIER VERSION OF THIS
# COMMENT SAID IT DID NOT. That false premise shipped in four places and drove a
# design decision; it is corrected here rather than quietly deleted. Atlassian
# documents `definitions: imports: <name>: <path>` with a same-repo path, and
# the imported file declares `export: true`. So Bitbucket gets a separate
# release file like the other two — it simply needs two wiring points instead of
# GitLab's one (the `imports` declaration, and an `import:` reference under the
# start-condition).
#
# What is genuinely NOT available on Bitbucket is GitLab's transparent
# `include:` — the imported pipeline must be referenced by name. That is the
# real asymmetry, and it is smaller than the one previously claimed.
#
# SYNC SIBLINGS: none, and keep it that way. This function replaced init.sh's
# own `case "$host"` precisely so the mapping has one owner — cf.
# `# BL-084-TIER-KEY`, which exists because a different predicate did grow
# copies. Callers ask; they do not re-derive.
HOST_CI_PATH=""
HOST_RELEASE_PATH=""
HOST_RELEASE_EXECUTES=""
host_pipeline_resolve() {
  local host="${1:-}"
  if [ -z "$host" ]; then
    host="$(host_read_from_manifest)" || return $?
  fi
  case "$host" in   # BL-229-HOST-PIPELINE-PATHS
    github)
      HOST_CI_PATH=".github/workflows/ci.yml"
      HOST_RELEASE_PATH=".github/workflows/release.yml"
      HOST_RELEASE_EXECUTES="file"
      ;;
    gitlab)
      HOST_CI_PATH=".gitlab-ci.yml"
      HOST_RELEASE_PATH=".gitlab-ci/release.yml"   # BL-229-HOST-PIPELINE-GITLAB
      HOST_RELEASE_EXECUTES="include"
      ;;
    bitbucket)
      HOST_CI_PATH="bitbucket-pipelines.yml"
      HOST_RELEASE_PATH="bitbucket-pipelines/release.yml"
      HOST_RELEASE_EXECUTES="import"
      ;;
    *)
      # FAIL CLOSED, and name the value. The arm this replaced defaulted an
      # unknown host to the GitHub paths behind a warning, which is how a
      # mis-recorded host silently produced a GitHub-shaped answer everywhere.
      HOST_CI_PATH=""; HOST_RELEASE_PATH=""; HOST_RELEASE_EXECUTES=""
      echo "host.sh: cannot resolve pipeline paths for host '$host'. Valid: github, gitlab, bitbucket" >&2
      return 4
      ;;
  esac
  return 0
}

# host_wire_release <ci_path> <release_path> <how> — make the release file
# REACHABLE from the root pipeline, and return non-zero if that did not happen.
#
# One owner, because there are now two callers (init.sh at scaffold time,
# verify-install.sh as an auto-fix) and a second copy of this is exactly the
# drift `# BL-229-HOST-PIPELINE-PATHS` exists to prevent.
#
# Prints NOTHING: callers own their own reporting vocabulary (print_info /
# register_fixable / …). The contract is the exit code and the file on disk.
#
#   0  the release file is referenced by the CI file (newly, or already)
#   1  it is not, and the caller must say so — an unreferenced release file
#      never executes, which is the defect this whole entry is about
#
# `sed`'s `r` reads a FILE after the matched line. Deliberately not `awk -v`:
# BSD awk rejects a newline in a -v assignment, and the first attempt at the
# Bitbucket wiring used exactly that — the splice never ran, the `&&`
# short-circuited, and the caller reported success anyway.
host_wire_release() {                                                # BL-229-WIRE-RELEASE
  local ci="$1" rel="$2" how="$3"
  [ "$how" = "file" ] && return 0            # GitHub: its own file, no wiring
  [ -f "$ci" ] || return 1                   # nothing to wire it into
  grep -q "$rel" "$ci" 2>/dev/null && return 0   # already wired; idempotent

  local frag tmp before after
  frag="$(mktemp)"; tmp="$(mktemp)"
  before="$(cksum < "$ci")"
  case "$how" in
    include)
      { printf '\n# Release pipeline (solo-orchestrator). Without this include the\n'
        printf '# file below is never evaluated by GitLab.\n'
        printf 'include:\n'
        printf '  - local: %s\n' "/$rel"
      } >> "$ci"
      ;;
    import)
      printf '  imports:\n    release: %s\n' "$rel" > "$frag"   # BL-229-IMPORT-WIRE
      if grep -q '^definitions:' "$ci"; then
        sed "/^definitions:[[:space:]]*\$/r $frag" "$ci" > "$tmp" && cat "$tmp" > "$ci"
      else
        { printf '\ndefinitions:\n'; cat "$frag"; } >> "$ci"
      fi
      printf "  tags:\n    'v*':\n      import: release-pipeline@release\n" > "$frag"
      if grep -q '^pipelines:' "$ci"; then
        sed "/^pipelines:[[:space:]]*\$/r $frag" "$ci" > "$tmp" && cat "$tmp" > "$ci"
      else
        { printf '\npipelines:\n'; cat "$frag"; } >> "$ci"
      fi
      ;;
    *) rm -f "$frag" "$tmp"; return 1 ;;
  esac
  after="$(cksum < "$ci")"
  rm -f "$frag" "$tmp"
  # VERIFY, then let the caller claim. "The command ran" is not "the file changed".
  [ "$before" != "$after" ] || return 1
  grep -q "$rel" "$ci" 2>/dev/null || return 1
  return 0
}

host_load_driver() {
  local host
  host=$(host_read_from_manifest) || return $?
  local root
  root=$(_host_repo_root)
  case "$host" in
    github|gitlab|bitbucket)
      local driver="$root/scripts/host-drivers/$host.sh"
      if [ ! -f "$driver" ]; then
        echo "host.sh: driver for '$host' not found at $driver" >&2
        return 3
      fi
      # shellcheck disable=SC1090
      source "$driver"
      ;;
    other)
      _host_define_other_fallbacks
      ;;
    *)
      echo "host.sh: unknown host '$host'. Valid: github, gitlab, bitbucket, other" >&2
      return 4
      ;;
  esac
}

_host_define_other_fallbacks() {
  host_name()                { echo "other"; }
  host_require_cli()         { return 0; }  # No CLI for 'other'; user provides URL
  host_create_repo()         { echo "host.sh: 'other' host requires user-supplied URL — call from init.sh interactively" >&2; return 10; }
  host_register_remote() {
    local url="${1:?url required}"
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin "$url"
    else
      git remote add origin "$url"
    fi
  }
  host_push_initial()        { git push -u origin "${1:-main}"; }
  host_configure_protection(){ echo "host.sh: 'other' host — branch protection via manual attestation only" >&2; return 0; }
  host_verify_protection() {
    # Read attestation from process-state.json
    local ps
    ps="$(_host_repo_root)/.claude/process-state.json"
    [ ! -f "$ps" ] && return 1
    local attested
    attested=$(jq -r '.phase2_init.attestations.branch_protection.at // empty' "$ps" 2>/dev/null || true)
    [ -z "$attested" ] && return 1
    # Check attestation age (90 days)
    local now then_ts days
    now=$(date +%s)
    # Try GNU date first, then BSD (macOS) date. Audit fix code-lib-1
    # (2026-06-28): pre-fix, dual-parser failure silently fell through
    # via `|| echo "$now"`, which made age=0 days and bypassed the
    # 90-day staleness check entirely. Now we fail-closed and name the
    # offending value on stderr so the operator can re-record the
    # attestation rather than silently waving the W3 backstop.
    #
    # Verifier follow-up (2026-06-28): variable renamed from `then`
    # to `then_ts`. bash permits `then` as a variable (it's a keyword
    # only in syntactic position) but several shell linters flag it;
    # the `_ts` suffix also makes the unit explicit (epoch seconds).
    if then_ts=$(date -d "$attested" +%s 2>/dev/null); then
      :
    elif then_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$attested" +%s 2>/dev/null); then
      :
    else
      echo "host.sh: unparseable branch_protection attestation timestamp: '$attested'" >&2
      return 1
    fi
    days=$(( (now - then_ts) / 86400 ))
    [ "$days" -gt 90 ] && return 1
    return 0
  }
}
