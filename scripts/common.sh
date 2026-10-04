# Sourced by the build scripts after they set REPO_ROOT. Resolves the target
# Ubuntu release and its per-release settings from VERSION.

# shellcheck source=../VERSION
source "$REPO_ROOT/VERSION"

# Target Ubuntu release: env var takes precedence, then auto-detect.
UBUNTU_VERSION="${UBUNTU_VERSION:-$(lsb_release -rs 2>/dev/null || echo "")}"
if [ -z "$UBUNTU_VERSION" ]; then
    echo "Error: cannot detect Ubuntu version. Set UBUNTU_VERSION env var." >&2
    exit 1
fi
export UBUNTU_VERSION
UBUNTU_VERSION_NODOT="${UBUNTU_VERSION//.}"

case "$UBUNTU_VERSION" in
    24.04) UBUNTU_CODENAME="noble" ;;
    26.04) UBUNTU_CODENAME="resolute" ;;
    *)
        echo "Error: Ubuntu ${UBUNTU_VERSION} is not supported." >&2
        echo "See AGENTS.md, \"Adding a new Ubuntu release\"." >&2
        exit 1
        ;;
esac

# Per-release settings, e.g. DEBIAN_REVISION_2404. An explicit
# SNAPSHOT_TIMESTAMP env var still overrides the VERSION value.
_rev_var="DEBIAN_REVISION_${UBUNTU_VERSION_NODOT}"
_snap_var="SNAPSHOT_TIMESTAMP_${UBUNTU_VERSION_NODOT}"
_build_var="UBUNTU_BUILD_${UBUNTU_VERSION_NODOT}"
DEBIAN_REVISION="${!_rev_var:-}"
if [ -z "$DEBIAN_REVISION" ]; then
    echo "Error: ${_rev_var} is not set in VERSION." >&2
    exit 1
fi
SNAPSHOT_TIMESTAMP="${SNAPSHOT_TIMESTAMP:-${!_snap_var:-}}"
UBUNTU_BUILD="${!_build_var:-1}"
