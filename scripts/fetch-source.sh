#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../VERSION
source "$REPO_ROOT/VERSION"

DSC_FILE="kodi_${KODI_VERSION}+dfsg-${DEBIAN_REVISION}.dsc"
POOL_URL="https://deb.debian.org/debian/pool/main/k/kodi/${DSC_FILE}"

# snapshot.debian.org fallback. Debian removes superseded source from the live
# pool (e.g. 21.3+dfsg-1 was replaced by the NMU -1.1), which makes the pool
# dget 404. snapshot.debian.org archives every upload permanently, so we fetch
# the exact pinned revision from there when the pool no longer carries it.
# SNAPSHOT_TIMESTAMP only needs to be a point when this revision was in the
# archive — the .dsc is GPG-signed and pins each component's SHA256, so the
# bytes are identical to the original pool upload regardless of the snapshot
# chosen (verified: same .dsc sha256 as the source the .1-.3 releases built).
SNAPSHOT_TIMESTAMP="${SNAPSHOT_TIMESTAMP:-20260201T000000Z}"
SNAPSHOT_URL="https://snapshot.debian.org/archive/debian/${SNAPSHOT_TIMESTAMP}/pool/main/k/kodi/${DSC_FILE}"

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
# before extracting — will abort if signature is invalid or untrusted. Try the
# live pool first; fall back to snapshot.debian.org if the revision has been
# superseded and dropped from the pool.
if ! dget "$POOL_URL"; then
    echo "" >&2
    echo "Live pool fetch failed — revision likely superseded from the pool." >&2
    echo "Falling back to snapshot.debian.org (${SNAPSHOT_TIMESTAMP})..." >&2
    dget "$SNAPSHOT_URL"
fi

# Also run dscverify explicitly so the full signature details appear in the
# build log, making it easy for anyone reviewing the CI output to confirm
# the source was cryptographically verified
echo ""
echo "=== GPG signature verification ==="
dscverify --keyring "$KEYRING" "$DSC_FILE"

echo ""
echo "Source extracted: build/kodi-${KODI_VERSION}+dfsg/"
