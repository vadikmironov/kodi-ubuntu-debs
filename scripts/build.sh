#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Resolves and exports UBUNTU_VERSION, so the child scripts build the same
# target release even when it is set explicitly rather than auto-detected.
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

SUDO=""
[ "$(id -u)" != "0" ] && SUDO="sudo"

echo "=== Installing base tooling ==="
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends \
    build-essential devscripts debhelper dh-python \
    dpkg-dev fakeroot lintian quilt equivs wget \
    debian-keyring

echo "=== Fetching Debian source ==="
bash "$SCRIPT_DIR/fetch-source.sh"

echo "=== Patching for Ubuntu ${UBUNTU_VERSION} ==="
bash "$SCRIPT_DIR/patch-for-ubuntu.sh"

SOURCE_DIR="$REPO_ROOT/build/kodi-${KODI_VERSION}+dfsg"
cd "$SOURCE_DIR"

# mk-build-deps generates a temporary .deb from debian/control's Build-Depends
# and installs it. This is more reliable than `apt-get build-dep` because it
# respects our patched debian/control constraints exactly.
echo "=== Installing build dependencies ==="
$SUDO mk-build-deps -i -t 'apt-get -y --no-install-recommends' || {
    echo "Warning: mk-build-deps returned non-zero, attempting recovery with apt-get -f install..." >&2
}
$SUDO apt-get -f install -y

# -us -uc: skip signing (unsigned source, unsigned changes) — not needed for
# local builds or CI artifacts. Only required when uploading to a PPA or repo.
echo "=== Building ==="
dpkg-buildpackage -us -uc -b -j"$(nproc)"

echo "=== Collecting output ==="
mkdir -p "$REPO_ROOT/output"
if ls "$REPO_ROOT/build/"*.deb >/dev/null 2>&1; then
    cp "$REPO_ROOT/build/"*.deb "$REPO_ROOT/output/"
    echo "Done. Packages in output/:"
    ls -lh "$REPO_ROOT/output/"
else
    echo "Error: no .deb files found in build/. Check the build log above." >&2
    exit 1
fi
