#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Resolves UBUNTU_VERSION, UBUNTU_CODENAME and UBUNTU_BUILD (see VERSION).
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

SOURCE_DIR="$REPO_ROOT/build/kodi-${KODI_VERSION}+dfsg"

echo "Patching for Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: source directory not found: $SOURCE_DIR" >&2
    echo "Run scripts/fetch-source.sh first." >&2
    exit 1
fi

# Optional: a release whose packaging needs no changes has no patch directory.
PATCH_DIR="$REPO_ROOT/patches/ubuntu-${UBUNTU_VERSION}"

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
        if ! (cd "$SOURCE_DIR" && QUILT_PATCHES=debian/patches quilt pop); then
            echo "Error: failed to unapply ffmpeg7 patch." >&2
            exit 1
        fi
        ;;
    *)
        echo "Keeping Debian ffmpeg7 patch (Ubuntu ${UBUNTU_VERSION} ships ffmpeg >= 7)."
        ;;
esac

# --- Step 2: Apply Ubuntu-specific patches to the debian/ directory.
# These patches modify debian/control (dependency names) and debian/patches/series
# (removing references to patches we unapplied in step 1).
[ -d "$PATCH_DIR" ] || echo "No Ubuntu ${UBUNTU_VERSION} packaging patches."
for patch in "$PATCH_DIR/"*.patch; do
    [ -f "$patch" ] || continue
    patchname=$(basename "$patch")
    echo "Applying ${patchname}..."
    if ! patch -d "$SOURCE_DIR" -p1 < "$patch"; then
        echo "Error: failed to apply patch: ${patchname}" >&2
        exit 1
    fi
done

# --- Step 2.5: Add upstream source backports.
# These patch Kodi *source* (not debian/ metadata) to backport fixes that are
# already in a newer Kodi release. They are tied to the current KODI_VERSION,
# not to any Ubuntu release — the same patch applies to every Ubuntu target —
# so they live here rather than in patches/ubuntu-<ver>/. They MUST be reviewed
# (and usually dropped) when KODI_VERSION is bumped: each patch's DEP-3 header
# records the upstream version that supersedes it (Applied-Upstream:). Each is a
# quilt patch: we drop it into debian/patches/backports/ and append it to the
# series so dpkg-buildpackage applies it during the build (after Debian's).
BACKPORTS_DIR="$REPO_ROOT/patches/backports"
if [ -d "$BACKPORTS_DIR" ]; then
    SERIES="$SOURCE_DIR/debian/patches/series"
    mkdir -p "$SOURCE_DIR/debian/patches/backports"
    for patch in "$BACKPORTS_DIR/"*.patch; do
        [ -f "$patch" ] || continue
        patchname=$(basename "$patch")
        echo "Adding common patch backports/${patchname}..."
        cp "$patch" "$SOURCE_DIR/debian/patches/backports/$patchname"
        # Append to the series only if not already present (idempotent).
        if ! grep -qxF "backports/$patchname" "$SERIES"; then
            echo "backports/$patchname" >> "$SERIES"
        fi
    done
fi

# --- Step 3: Update changelog.
# Set an explicit version <debian-version>~ubuntu<NODOT><UBUNTU_BUILD>, e.g.
# 2:21.3+dfsg-1~ubuntu24042. We build the version ourselves (rather than
# `dch --local`, whose auto-incrementing trailing counter is not deterministic
# on a fresh extract) so re-releases bump predictably with UBUNTU_BUILD. The
# trailing digit is the build number, continuing the published scheme where
# the first release was ~ubuntu<NODOT>1 (e.g. ~ubuntu24041). The leading "~"
# keeps it sorting below any hypothetical official Ubuntu kodi of the same
# version. -b/--force-bad-version is required because ~ sorts *below* the plain
# Debian version, so dch would otherwise reject it as "not greater".
# --force-distribution is needed because the codename (e.g. "noble") may not
# match the running system's distribution.
echo "Updating changelog..."
(
    cd "$SOURCE_DIR"
    BASE_VERSION="$(dpkg-parsechangelog -S Version)"
    NEW_VERSION="${BASE_VERSION}~ubuntu${UBUNTU_VERSION_NODOT}${UBUNTU_BUILD}"
    echo "New package version: ${NEW_VERSION}"
    DEBEMAIL="builder@ubuntu.local" DEBFULLNAME="Ubuntu Builder" \
        dch -b -v "$NEW_VERSION" \
        --distribution "$UBUNTU_CODENAME" --force-distribution \
        "Backport to Ubuntu ${UBUNTU_VERSION} LTS (rebuild ${UBUNTU_BUILD})"
)
