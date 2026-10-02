#!/usr/bin/env bash
set -uo pipefail

# scripts/install-gitleaks.sh — install a PINNED, CHECKSUM-VERIFIED gitleaks on
# Linux. The tool matrix's linux_apt / linux_dnf / linux_pacman rows name this
# script; macOS uses `brew install gitleaks` and never reaches it.
#
# `## BL-316:` the rows it replaces were `GITLEAKS_VERSION=$(curl … | jq …)`
# followed by `curl … | sudo tar …`: an unpinned `latest`, never verified, and
# always the x64 asset (so an arm64 host got a binary it cannot execute).
# verify-install.sh's install path REFUSES that shape — `$(` and `|` are the
# chaining metacharacters it exists to stop — so its auto-install could never
# run on Linux. Loosening that refusal is not the fix; a vetted script is.
#
# The pins match `.github/workflows/tests.yml`'s `Install gitleaks (pinned +
# checksum-verified)` step (x64), and both digests are the release's own: the
# GitHub release-asset `digest` field and `gitleaks_8.30.1_checksums.txt`
# agree for each, read 2026-10-01 without downloading either binary.
#
# Exit: 0 installed; 1 refused or failed (nothing is installed on any refusal).

GITLEAKS_VERSION="8.30.1"
GITLEAKS_SHA256_LINUX_X64="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
GITLEAKS_SHA256_LINUX_ARM64="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"
INSTALL_DIR="/usr/local/bin"
RELEASES_URL="https://github.com/gitleaks/gitleaks/releases"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

refuse() {
  echo "install-gitleaks: REFUSED — $1" >&2
  echo "install-gitleaks: nothing was installed. Install gitleaks yourself: $RELEASES_URL" >&2
  exit 1
}

_os="$(uname -s 2>/dev/null)"
[ "$_os" = "Linux" ] || refuse "this installer is for Linux (this host is '${_os:-unknown}'); on macOS run: brew install gitleaks"

_machine="$(uname -m 2>/dev/null)"
case "$_machine" in
  x86_64|amd64)  asset_arch="x64";   sha="$GITLEAKS_SHA256_LINUX_X64" ;;     # BL-316-ARCH-X64
  aarch64|arm64) asset_arch="arm64"; sha="$GITLEAKS_SHA256_LINUX_ARM64" ;;   # BL-316-ARCH-ARM64
  *) refuse "no pinned checksum for machine type '${_machine:-unknown}' (pinned: x86_64, aarch64)" ;;   # BL-316-ARCH-OTHER
esac

# Checked BEFORE the download: without the verifier nothing may be fetched.
verifier="$here/ci-verify-sha256.sh"
[ -f "$verifier" ] || refuse "the checksum verifier is missing ($verifier), so the download could not be verified"   # BL-316-VERIFIER-PRESENT

tmp="$(mktemp -d)" || refuse "could not create a temporary directory"
trap 'rm -rf "$tmp"' EXIT

asset="gitleaks_${GITLEAKS_VERSION}_linux_${asset_arch}.tar.gz"
url="$RELEASES_URL/download/v${GITLEAKS_VERSION}/$asset"
echo "install-gitleaks: downloading $url" >&2
curl -sSfL --retry 3 -o "$tmp/$asset" "$url" || refuse "download failed: $url"

bash "$verifier" "$tmp/$asset" "$sha" >&2 || refuse "$asset did not match its pinned SHA-256"   # BL-316-CHECKSUM

tar -xzf "$tmp/$asset" -C "$tmp" gitleaks || refuse "could not extract gitleaks from $asset"
[ -f "$tmp/gitleaks" ] || refuse "$asset did not contain a gitleaks binary"

sudo install -m 0755 "$tmp/gitleaks" "$INSTALL_DIR/gitleaks" || refuse "could not install to $INSTALL_DIR/gitleaks"
echo "install-gitleaks: installed gitleaks $GITLEAKS_VERSION (linux_$asset_arch, sha256 verified) at $INSTALL_DIR/gitleaks" >&2
exit 0
