# AGENTS.md — kodi-ubuntu-debs

Build tooling repo that produces native Kodi `.deb` packages for Ubuntu LTS releases, backported from official Debian packaging. No Kodi source code lives here.

## What this repo does

1. `scripts/fetch-source.sh` — downloads the Debian source package (`.dsc` + tarballs) from `deb.debian.org` using `dget`, verifies GPG signature against the Debian keyring (via `dscverify`), and extracts it into `build/`
2. `scripts/patch-for-ubuntu.sh` — detects (or accepts via `UBUNTU_VERSION` env var) the target Ubuntu release, conditionally unapplies incompatible Debian quilt patches (e.g. ffmpeg7 on 24.04), then applies patches from `patches/ubuntu-<version>/` to the extracted `debian/` directory
3. `scripts/build.sh` — end-to-end orchestrator: detects Ubuntu version, exports it, calls the two scripts above, installs build-deps via `mk-build-deps`, runs `dpkg-buildpackage`, copies output to `output/`

## Patch system

Patches live in `patches/ubuntu-<version>/` — one directory per supported Ubuntu LTS release. Each patch modifies only `debian/` metadata — never Kodi application source.

Current patches for Ubuntu 24.04:
- `control.patch` — renames `libtag-dev` → `libtag1-dev` (Ubuntu package name differs from Debian)
- `series.patch` — removes `0004-ffmpeg7.patch` from `debian/patches/series` (that patch targets ffmpeg 7.x; Ubuntu 24.04 ships ffmpeg 6.1.1, which Kodi 21 already supports natively)

**Important ordering in `patch-for-ubuntu.sh`:** The quilt pop (step 1) MUST happen before our patches are applied (step 2), because `series.patch` modifies `debian/patches/series` which is the file quilt reads. Reversing this order breaks quilt's internal state.

## Ubuntu version detection

All scripts resolve the target Ubuntu version using this precedence:
1. `UBUNTU_VERSION` env var (explicit override)
2. `lsb_release -rs` auto-detection from the running system

The workflow passes `UBUNTU_VERSION` explicitly via the matrix. Local builds auto-detect.

## Adding a new Ubuntu release

1. **Create patch directory:** `patches/ubuntu-<version>/` with patches for that release
2. **Add codename mapping** in `scripts/patch-for-ubuntu.sh`:
   ```bash
   case "$UBUNTU_VERSION" in
       24.04) UBUNTU_CODENAME="noble" ;;
       26.04) UBUNTU_CODENAME="<codename>" ;;   # add here
   ```
3. **Review ffmpeg patch logic** in `patch-for-ubuntu.sh`: the `case` statement in step 1 controls which Debian patches to unapply. If the new release ships ffmpeg 7.x, it should fall through to the `*` case which skips the pop. If it ships ffmpeg 6.x, add an explicit case.
4. **Add to workflow matrix** in `.github/workflows/build.yml`:
   ```yaml
   ubuntu-version: ['24.04', '26.04']
   ```
5. **Document pitfalls** in the "Known pitfalls" section below and in `README.md`'s Troubleshooting table
6. **Test locally:** `UBUNTU_VERSION=26.04 bash scripts/build.sh` on a 26.04 VM

## Versioning

All Kodi/Debian version info is in the `VERSION` file at the repo root:
```
KODI_VERSION=21.3
DEBIAN_REVISION=1
```
All scripts and the workflow source this file — it's the single place to bump when a new Kodi point release comes out.

Release tags are per-Ubuntu: `v21.3-1ubuntu2404.1`, `v21.3-1ubuntu2604.1`, etc.

## Key external URLs

- Debian source (.dsc): https://deb.debian.org/debian/pool/main/k/kodi/
- Debian packaging git: https://salsa.debian.org/multimedia-team/kodi-media-center/kodi.git
- Debian package tracker: https://tracker.debian.org/pkg/kodi
- Kodi upstream (Omega branch): https://github.com/xbmc/xbmc/tree/Omega
- Ubuntu build guide: https://github.com/xbmc/xbmc/blob/master/docs/README.Ubuntu.md
- Ubuntu releases & codenames: https://wiki.ubuntu.com/Releases
- GH Actions dpkg-genbuildinfo slowness issue: https://github.com/actions/runner-images/issues/13150
- GitHub artifact attestations: https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations
- SLSA provenance: https://slsa.dev

## Known pitfalls by Ubuntu release

### Ubuntu 24.04 (Noble)
- **ffmpeg 6.1 vs Debian's 7.x pins** — `debian/control` pins exact ffmpeg 7.x library versions; relax these to `>=` constraints matching 6.1
- **`0004-ffmpeg7.patch`** — Debian patch adds ffmpeg 7.x API compat; unapplied via `quilt pop` in `patch-for-ubuntu.sh` step 1 when targeting 24.04
- **libtag naming** — Ubuntu calls it `libtag1-dev`; Debian calls it `libtag-dev` (handled by `control.patch`)
- **fmt/spdlog** — if versions are too old, add `-DENABLE_INTERNAL_FMT=ON -DENABLE_INTERNAL_SPDLOG=ON` to cmake args in `debian/rules`

### Ubuntu 26.04 (codename TBD — not yet released as of this writing)
- ffmpeg version unknown at time of writing — check `apt-cache policy libavcodec-dev` on a 26.04 system
- If ffmpeg 7.x: the `0004-ffmpeg7.patch` quilt pop is skipped automatically; `series.patch` may not be needed
- Verify libtag package name — may differ again

### General (all releases)
- **`dpkg-genbuildinfo` slowness** — GH runners have a huge `/usr/local`; workflow renames it before build
- **Disk space** — workflow removes Android SDK, .NET, ghcup, PowerShell to free ~15 GB before building
- **OOM during build** — if runner runs out of RAM, fall back to `-j2`

## Refreshing patches for a new Kodi version

1. Bump `VERSION`
2. Run `scripts/fetch-source.sh` locally — extracts new source into `build/`
3. Try applying existing patches: `UBUNTU_VERSION=24.04 bash scripts/patch-for-ubuntu.sh`
4. If patches fail, inspect what changed in `debian/control` and `debian/patches/series` in the new version and update accordingly
5. Regenerate patches with `diff -u` against the original extracted `debian/` files

## Validation checklist

For each supported Ubuntu release:
- [ ] `UBUNTU_VERSION=<ver> bash scripts/build.sh` completes end-to-end on a clean Ubuntu `<ver>` VM
- [ ] GitHub Actions workflow passes on push to `main` (all matrix entries green)
- [ ] Workflow artifacts contain `.deb` files named with the correct Ubuntu version
- [ ] Tag push triggers Release with `.deb`, `SHA256SUMS`, and per-distro build logs attached
- [ ] `sudo dpkg -i kodi-data_*.deb kodi-bin_*.deb kodi_*.deb && sudo apt -f install` succeeds on clean Ubuntu `<ver>`
- [ ] `kodi --version` shows the expected version (the Git hash and branch name vary per build, but version and codename should match, e.g. `21.3.0 ... Omega`)
- [ ] GPG verification step in `fetch-source.sh` passes and is visible in the build log
