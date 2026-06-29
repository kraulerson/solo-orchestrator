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
