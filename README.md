# kodi-ubuntu-debs

Unofficial Kodi 21.3 (Omega) `.deb` packages for Ubuntu LTS, backported from Debian unstable packaging.

GitHub Actions builds the packages on every push and publishes them as downloadable artifacts. Tagged releases attach the `.deb` files to a GitHub Release page.

## Why

The official Kodi PPA has been abandoned and no longer publishes packages for current Ubuntu LTS releases. The Flatpak version has known issues with Nvidia drivers and sandbox restrictions. This repository provides native `.deb` packages built from the same source used by Debian, with the minimal changes needed to build on each supported Ubuntu LTS release.

## Supported Ubuntu releases

| Ubuntu | Architecture | Status |
|--------|-------------|--------|
| 24.04 LTS (Noble) | amd64 | Supported |
| 26.04 LTS | amd64 | Planned |

Only x86_64 (amd64) is supported. Building for other architectures (ARM64, i386) would require additional build matrix entries and architecture-specific patches.

## Install

Download the three core `.deb` files from the [latest Release](../../releases/latest) for your Ubuntu version:

- `kodi-data_*.deb`
- `kodi-bin_*.deb`
- `kodi_*.deb`

Then install:

```bash
sudo dpkg -i kodi-data_*.deb kodi-bin_*.deb kodi_*.deb
sudo apt -f install
```

`apt -f install` resolves and pulls in any missing runtime dependencies automatically.

## Build locally

Requires a supported Ubuntu LTS release. Run on a clean machine or VM — the build installs a large number of development packages.

```bash
git clone https://github.com/YOUR_USERNAME/kodi-ubuntu-debs.git
cd kodi-ubuntu-debs
bash scripts/build.sh
```

The target Ubuntu version is auto-detected from `lsb_release`. To build for a specific version explicitly:

```bash
UBUNTU_VERSION=24.04 bash scripts/build.sh
```

Packages are written to `output/` when the build completes.

## How it works

The repository contains no Kodi source code. At build time:

1. `scripts/fetch-source.sh` downloads the Debian source package (`kodi_21.3+dfsg-1.dsc`) from the official Debian archive using `dget`, which verifies the GPG signature against the Debian keyring and extracts with `dpkg-source`. The signature details are printed to the build log via an explicit `dscverify` call.
2. `scripts/patch-for-ubuntu.sh` conditionally unapplies Debian patches incompatible with the target Ubuntu release (via `quilt pop`), then applies patches from `patches/ubuntu-<version>/` to the `debian/` metadata. Current patches for Ubuntu 24.04:
   - **`control.patch`** — renames `libtag-dev` to `libtag1-dev` (Ubuntu's package name differs from Debian's)
   - **`series.patch`** — removes the Debian `0004-ffmpeg7.patch` from the patch series, since that patch requires ffmpeg 7.x but Ubuntu 24.04 ships ffmpeg 6.1.1, which already satisfies Kodi 21's original requirements
3. `scripts/build.sh` installs build dependencies and runs `dpkg-buildpackage` to produce the `.deb` files.

## Releasing

Each Ubuntu release gets its own tag, using the format `v<KODI_VERSION>-<DEBIAN_REVISION>ubuntu<DISTRO>.<BUILD>`:

```bash
git tag v21.3-1ubuntu2404.1   # Ubuntu 24.04 build
git tag v21.3-1ubuntu2604.1   # Ubuntu 26.04 build (when available)
git push --tags
```

A tag push triggers the release job, which creates a GitHub Release with the `.deb` files, `SHA256SUMS`, and per-distro build logs attached.

## Contributing

Fork the repo, make your changes, and push — GitHub Actions builds automatically. Keep patches minimal: they should only touch `debian/` metadata, never Kodi source code.

### Adding a new Ubuntu release

1. Create `patches/ubuntu-<version>/` (e.g. `patches/ubuntu-26.04/`) with patches for that release
2. Add the new version to the matrix in `.github/workflows/build.yml`:
   ```yaml
   ubuntu-version: ['24.04', '26.04']
   ```
3. Add the codename mapping to `scripts/patch-for-ubuntu.sh`:
   ```bash
   26.04) UBUNTU_CODENAME="<codename>" ;;
   ```
4. Review the ffmpeg `quilt pop` logic in `patch-for-ubuntu.sh` — if the new release ships ffmpeg 7.x, ensure the pop is skipped
5. Document any release-specific pitfalls in `CLAUDE.md` and the Troubleshooting table below

## Troubleshooting

| Problem | Solution | Applies to |
|---------|----------|------------|
| `dpkg-checkbuilddeps` ffmpeg version mismatch | Relax version pins in `debian/control` to match the Ubuntu release's ffmpeg version | Ubuntu 24.04 (ffmpeg 6.1) |
| Debian patches add ffmpeg 7.x compat that breaks on 6.1 | Remove those patches from `debian/patches/series` | Ubuntu 24.04 |
| fmt/spdlog version too old | Add `-DENABLE_INTERNAL_FMT=ON -DENABLE_INTERNAL_SPDLOG=ON` to cmake args in `debian/rules` | Ubuntu 24.04 |
| Quilt patch fails to apply | Use `quilt push -a --fuzz=3` for minor context drift, or inspect the `.rej` file and update the patch manually | General |
| Build OOM killed on GH runner | Reduce to `-j2` in `dpkg-buildpackage` | General |
| Disk full on GH runner | Free more space — remove `/opt/hostedtoolcache`, `/usr/local/lib/android`, etc. | General |
| `dpkg-genbuildinfo` takes 15+ min | `sudo mv /usr/local /usr/local.bak` before build (already in workflow) | General |

## Updating to a new Kodi version

Edit the single `VERSION` file at the repo root:

```
KODI_VERSION=21.3
DEBIAN_REVISION=1
```

Bump `KODI_VERSION` to the new point release (e.g. `21.4`) and push. GitHub Actions will pick it up automatically. If the new Debian source package has changed in ways that break the patches, the build log will make it clear what needs updating.

## Known limitations

- No GPU in CI — GitHub Actions runners have no display hardware, so rendering is not tested. The packages install and `kodi --version` is verified but actual playback is not.
- Nvidia users need to ensure their proprietary drivers are correctly installed separately.
- Add-on packages are not included — only the core `kodi`, `kodi-bin`, and `kodi-data` packages are published as release assets. The full set of built packages (event clients, dev headers, etc.) is available as workflow artifacts.

## Trust & verification

This repository contains no Kodi application code. The only files here are:

- Shell scripts that orchestrate the build
- Small patches per Ubuntu release that modify build metadata only (`debian/control` and `debian/patches/series`) — not Kodi source code
- A GitHub Actions workflow

Kodi source is fetched at build time directly from the official Debian archive (`deb.debian.org`) and its GPG signature is verified against the Debian keyring. You can audit every patch in `patches/` — they are short and straightforward.

Each release includes SLSA build provenance attestations, verifiable with:

```bash
gh attestation verify kodi_*.deb --owner YOUR_USERNAME
```

## External resources

- [Debian New Maintainers' Guide](https://www.debian.org/doc/manuals/maint-guide/) — comprehensive guide to Debian packaging
- [dget(1)](https://manpages.debian.org/dget) — download Debian source packages
- [dscverify(1)](https://manpages.debian.org/dscverify) — verify Debian source package signatures
- [quilt(1)](https://manpages.debian.org/quilt) — manage sets of patches
- [dpkg-buildpackage(1)](https://manpages.debian.org/dpkg-buildpackage) — build Debian packages from source
- [Ubuntu releases & codenames](https://wiki.ubuntu.com/Releases)

## License

MIT — see [LICENSE](LICENSE).

Kodi itself is licensed under GPL-2.0. This repository only contains build tooling.
