#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../VERSION
source "$REPO_ROOT/VERSION"

# Detect Ubuntu version: env var takes precedence, then auto-detect from runner
UBUNTU_VERSION="${UBUNTU_VERSION:-$(lsb_release -rs 2>/dev/null || echo "")}"
if [ -z "$UBUNTU_VERSION" ]; then
    echo "Error: cannot detect Ubuntu version. Set UBUNTU_VERSION env var." >&2
    exit 1
fi

# Map version number to Debian distribution codename.
# For new releases not listed here, set UBUNTU_CODENAME env var explicitly.
case "$UBUNTU_VERSION" in
    24.04) UBUNTU_CODENAME="noble" ;;
    *)
        UBUNTU_CODENAME="${UBUNTU_CODENAME:-}"
        if [ -z "$UBUNTU_CODENAME" ]; then
            echo "Error: no codename mapping for Ubuntu ${UBUNTU_VERSION}." >&2
            echo "Set UBUNTU_CODENAME env var (e.g. UBUNTU_CODENAME=plucky)" >&2
            exit 1
        fi
        ;;
esac

UBUNTU_VERSION_NODOT="${UBUNTU_VERSION//.}"
SOURCE_DIR="$REPO_ROOT/build/kodi-${KODI_VERSION}+dfsg"

echo "Patching for Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: source directory not found: $SOURCE_DIR" >&2
    echo "Run scripts/fetch-source.sh first." >&2
    exit 1
fi

PATCH_DIR="$REPO_ROOT/patches/ubuntu-${UBUNTU_VERSION}"
if [ ! -d "$PATCH_DIR" ]; then
    echo "Error: no patch directory found for Ubuntu ${UBUNTU_VERSION}: $PATCH_DIR" >&2
    exit 1
fi

# --- Step 1: Conditionally unapply Debian patches that are incompatible with
# this Ubuntu release. This MUST happen before our patches modify the
# debian/patches/series file, to keep quilt's internal state consistent.
#
# The Debian 0004-ffmpeg7.patch updates FindFFMPEG.cmake to require ffmpeg 7.x
# and makes API compat changes throughout the source. Only unapply it on Ubuntu
# releases that ship ffmpeg 6.x — on releases with ffmpeg 7.x it should stay.
case "$UBUNTU_VERSION" in
    24.04)
        echo "Unapplying Debian ffmpeg7 patch (Ubuntu ${UBUNTU_VERSION} ships ffmpeg 6.1)..."
        if ! QUILT_PATCHES=debian/patches quilt pop -d "$SOURCE_DIR"; then
            echo "Error: failed to unapply ffmpeg7 patch." >&2
            exit 1
        fi
        ;;
    *)
        echo "Skipping ffmpeg7 patch unapply (Ubuntu ${UBUNTU_VERSION} may ship ffmpeg 7.x — verify)."
        ;;
esac

# --- Step 2: Apply Ubuntu-specific patches to the debian/ directory.
# These patches modify debian/control (dependency names) and debian/patches/series
# (removing references to patches we unapplied in step 1).
for patch in "$PATCH_DIR/"*.patch; do
    [ -f "$patch" ] || continue
    patchname=$(basename "$patch")
    echo "Applying ${patchname}..."
    if ! patch -d "$SOURCE_DIR" -p1 < "$patch"; then
        echo "Error: failed to apply patch: ${patchname}" >&2
        exit 1
    fi
done

# --- Step 3: Update changelog.
# --force-distribution is needed because the target codename (e.g. "noble") may
# not match the running system's distribution.
echo "Updating changelog..."
(
    cd "$SOURCE_DIR"
    DEBEMAIL="builder@ubuntu.local" DEBFULLNAME="Ubuntu Builder" \
        dch --local ~ubuntu${UBUNTU_VERSION_NODOT} --distribution "$UBUNTU_CODENAME" \
        --force-distribution "Backport to Ubuntu ${UBUNTU_VERSION} LTS"
)
