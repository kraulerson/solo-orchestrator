#!/usr/bin/env bash
# scripts/ci-verify-sha256.sh FILE EXPECTED_SHA256
#
# Verify a downloaded artifact against a pinned SHA-256, by COMPUTING the hash
# and COMPARING IT IN THE SHELL — never by handing a checklist to `sha256sum -c`.
#
# WHY THIS EXISTS AS A SCRIPT RATHER THAN THREE LINES IN A WORKFLOW (R-WP2-6).
#
# The obvious spelling is a check that cannot fail:
#
#   $ echo "THIS-IS-NOT-A-HASH  gl.tgz" | sha256sum -c -
#   sha256sum: WARNING: 1 line is improperly formatted
#   rc=0
#
# Measured on this host (Darwin, /sbin/sha256sum). A MALFORMED pin — a typo, a
# truncated paste, a variable that expanded to nothing — makes the verification
# silently pass while verifying NOTHING. GNU coreutils is documented to exit
# non-zero for that case, but the CI step this protects would then be relying on
# which platform's binary happened to answer, and "it fails on the runner" is
# not a property you can execute on a laptop. Compute-and-compare has identical
# behaviour everywhere and needs no platform assumption.
#
# It is a SCRIPT because it has to be executable by a test. A verification step
# embedded in workflow YAML cannot be run by anything except CI, which means its
# failure modes cannot be proven — and an unprovable security check on the path
# that gates a planted-secret proof is precisely the shape of defect the WP2
# package exists to prevent. Both workflow jobs call this file; the K cases in
# tests/test-brownfield-wp2-scout-sections.sh execute every one of its failure
# modes.
#
# EXIT CODES, never labels: 0 the file matches the pin; 1 it does not, or
# either value is not a well-formed hash; 2 bad usage.
set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: ci-verify-sha256.sh <file> <expected-sha256>" >&2
  exit 2
fi

_file="$1"
_expected="$2"

if [ ! -f "$_file" ]; then
  echo "ci-verify-sha256: no such file: $_file" >&2
  exit 1
fi

# _is_sha256 VALUE — exactly 64 lowercase hex characters.
#
# Both sides are checked, not just the pin. An empty or truncated COMPUTED
# value is the other half of the same defect: if the hashing tool is missing or
# its output shape changes, an unchecked `computed` could compare equal to an
# equally-empty `expected` and report success having hashed nothing.
_is_sha256() {
  case "$1" in
    ""|*[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 64 ]
}

if ! _is_sha256 "$_expected"; then
  echo "ci-verify-sha256: the PINNED hash is not 64 lowercase hex characters — refusing to treat this as verified." >&2
  echo "ci-verify-sha256:   pin was: '$_expected'" >&2
  exit 1
fi

# GNU first, BSD second — the house portability rule. `awk` takes field 1
# because the two tools disagree about the rest of the line.
_computed=$( { sha256sum "$_file" 2>/dev/null || shasum -a 256 "$_file" 2>/dev/null; } | awk '{print $1; exit}' )

if ! _is_sha256 "$_computed"; then
  echo "ci-verify-sha256: could not compute a SHA-256 for $_file (no usable sha256sum/shasum, or unexpected output)." >&2
  echo "ci-verify-sha256:   got: '$_computed'" >&2
  exit 1
fi

if [ "$_computed" != "$_expected" ]; then
  echo "ci-verify-sha256: CHECKSUM MISMATCH for $_file" >&2
  echo "ci-verify-sha256:   expected $_expected" >&2
  echo "ci-verify-sha256:   computed $_computed" >&2
  exit 1
fi

echo "ci-verify-sha256: OK $_file ($_computed)"
exit 0
