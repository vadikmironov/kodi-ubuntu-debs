#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../VERSION
source "$REPO_ROOT/VERSION"

DSC_FILE="kodi_${KODI_VERSION}+dfsg-${DEBIAN_REVISION}.dsc"
DSC_URL="https://deb.debian.org/debian/pool/main/k/kodi/${DSC_FILE}"
KEYRING="/usr/share/keyrings/debian-keyring.gpg"

# Verify the Debian keyring is available before attempting to download.
# Install with: sudo apt-get install debian-keyring
if [ ! -f "$KEYRING" ]; then
    echo "Error: Debian keyring not found at ${KEYRING}" >&2
    echo "Install it with: sudo apt-get install debian-keyring" >&2
    exit 1
fi

mkdir -p "$REPO_ROOT/build"
cd "$REPO_ROOT/build"

echo "Fetching Debian source: kodi ${KODI_VERSION}+dfsg-${DEBIAN_REVISION}"

# dget without -u verifies the GPG signature against the installed keyrings
# before extracting — will abort if signature is invalid or untrusted
dget "$DSC_URL"

# Also run dscverify explicitly so the full signature details appear in the
# build log, making it easy for anyone reviewing the CI output to confirm
# the source was cryptographically verified
echo ""
echo "=== GPG signature verification ==="
dscverify --keyring "$KEYRING" "$DSC_FILE"

echo ""
echo "Source extracted: build/kodi-${KODI_VERSION}+dfsg/"
