# AGENTS.md — kodi-ubuntu-debs

Build tooling repo that produces native Kodi `.deb` packages for Ubuntu LTS releases, backported from official Debian packaging. No Kodi source code lives here.

## What this repo does

1. `scripts/fetch-source.sh` — downloads the Debian source package (`.dsc` + tarballs) pinned for the target release in `VERSION` from `deb.debian.org` using `dget`, verifies GPG signature against the Debian keyring (via `dscverify`), and extracts it into `build/`. If the pinned revision has been dropped from the live pool (Debian removes superseded source), it falls back to `snapshot.debian.org`, which archives every upload permanently.
2. `scripts/patch-for-ubuntu.sh` — detects (or accepts via `UBUNTU_VERSION` env var) the target Ubuntu release, conditionally unapplies incompatible Debian quilt patches (e.g. ffmpeg7 on 24.04), then applies patches from `patches/ubuntu-<version>/` to the extracted `debian/` directory
3. `scripts/build.sh` — end-to-end orchestrator: detects Ubuntu version, exports it, calls the two scripts above, installs build-deps via `mk-build-deps`, runs `dpkg-buildpackage`, copies output to `output/`

## Patch system

There are two kinds of patches, distinguished by what they change and what they're scoped to:

- **`patches/ubuntu-<version>/`** — one directory per supported Ubuntu LTS release. Each patch modifies only `debian/` metadata (e.g. `control`, `series`) — never Kodi application source. These exist because Ubuntu differs from Debian (package names, available library versions).
- **`patches/backports/`** — upstream Kodi *source* patches backported from a *newer* Kodi release to fix bugs in the version we currently build. They are **not** Ubuntu-specific (the same patch applies to every Ubuntu target) but they **are** tied to the current `KODI_VERSION`. `patch-for-ubuntu.sh` (step 2.5) copies them into `debian/patches/backports/` and appends them to the quilt series, so `dpkg-buildpackage` applies them after Debian's own patches. Each carries a DEP-3 header whose `Applied-Upstream:` field records the Kodi version that already contains the fix — **review and usually drop these when `KODI_VERSION` is bumped** (see "Refreshing patches for a new Kodi version").

Current patches for Ubuntu 24.04:
- `control.patch` — renames `libtag-dev` → `libtag1-dev` (Ubuntu package name differs from Debian)
- `series.patch` — removes `0004-ffmpeg7.patch` from `debian/patches/series` (that patch targets ffmpeg 7.x; Ubuntu 24.04 ships ffmpeg 6.1.1, which Kodi 21 already supports natively)

Ubuntu 26.04 needs none, so it has no `patches/ubuntu-26.04/` (the directory is optional).

**Important ordering in `patch-for-ubuntu.sh`:** The quilt pop (step 1) MUST happen before our patches are applied (step 2), because `series.patch` modifies `debian/patches/series` which is the file quilt reads. Reversing this order breaks quilt's internal state.

## Ubuntu version detection

All three scripts source `scripts/common.sh`, which resolves the target release (`UBUNTU_VERSION` env var, else `lsb_release -rs`), maps it to a codename, and reads that release's `DEBIAN_REVISION_<NODOT>`, `SNAPSHOT_TIMESTAMP_<NODOT>` and `UBUNTU_BUILD_<NODOT>` from `VERSION`. Unknown releases fail fast.

The workflow passes `UBUNTU_VERSION` explicitly via the matrix. Local builds auto-detect.

## Adding a new Ubuntu release

1. **`VERSION`:** add `DEBIAN_REVISION_<NODOT>`, `SNAPSHOT_TIMESTAMP_<NODOT>`, `UBUNTU_BUILD_<NODOT>=1`. Pick a Debian revision whose version sorts above Ubuntu's stock kodi if the release ships one (`dpkg --compare-versions`).
2. **`scripts/common.sh`:** add the codename mapping.
3. **Workflow:** add the version to `ALL` in the `setup` job; add the codename mapping and a reprepro stanza in `update-apt-repo`.
4. **Packaging patches (only if needed):** `patches/ubuntu-<version>/`; review the ffmpeg `quilt pop` case in `patch-for-ubuntu.sh`.
5. **Document pitfalls** below and in `README.md`'s Troubleshooting table.
6. **Test:** `UBUNTU_VERSION=<ver> bash scripts/build.sh` on that release (a VM or an `ubuntu:<ver>` container).

## Versioning

All Kodi/Debian version info is in the `VERSION` file at the repo root: a shared `KODI_VERSION`, plus per release (`<NODOT>` = `2404`, `2604`) the Debian revision, a snapshot timestamp for it, and the rebuild counter:
```
KODI_VERSION=21.3
DEBIAN_REVISION_2404=1     SNAPSHOT_TIMESTAMP_2404=...  UBUNTU_BUILD_2404=4
DEBIAN_REVISION_2604=1.1   SNAPSHOT_TIMESTAMP_2604=...  UBUNTU_BUILD_2604=1
```
All scripts (via `scripts/common.sh`) and the workflow source this file — it's the single place to bump when a new Kodi point release comes out. When 26.04 moves to Kodi 22 while 24.04 stays on 21.x, `KODI_VERSION` and `patches/backports/` will have to become per-release too.

`UBUNTU_BUILD_<NODOT>` is a rebuild counter for re-releasing the *same* Kodi/Debian version — e.g. after adding or changing a `patches/backports/` patch. `patch-for-ubuntu.sh` sets the package version to `<debian-version>~ubuntu<NODOT><UBUNTU_BUILD>` (e.g. `2:21.3+dfsg-1~ubuntu24044` for 24.04 build 4), so a bump makes apt treat the package as an upgrade. Bump it for every re-release; **reset it to 1 whenever `KODI_VERSION` changes**.

The trailing digit *is* the build number. The earlier 24.04 releases (tags `.1`–`.3`) predate this field and all shipped as `~ubuntu24041`; build 4 (`~ubuntu24044`, tag `.4`) is the first to carry the PipeWire backport, and from here the tag's trailing number tracks `UBUNTU_BUILD`. Note the suffix is concatenated with no separator — a dotted form like `~ubuntu2404.2` would sort *below* `~ubuntu24041` (because `2404` < `24041` numerically), i.e. a downgrade. Verify ordering with `dpkg --compare-versions` if you change the scheme.

Release tags are per-Ubuntu and end with the build number: `v21.3-1ubuntu2404.4`, `v21.3-1.1ubuntu2604.1`, etc. The trailing number should match that release's `UBUNTU_BUILD_<NODOT>`. A tag builds and publishes only its own release (the workflow's `setup` job parses it); pushes to `main` and PRs build every release.

## APT repository (GitHub Pages)

Packages are published to a GitHub Pages-hosted apt repository at
`https://vadikmironov.github.io/kodi-ubuntu-debs/`. The `update-apt-repo`
workflow job runs on tag pushes (in parallel with `release`), using `reprepro`
to build signed repository metadata and pushing the result to the `gh-pages` branch.

**Infrastructure:**
- **GPG signing key:** Ed25519, stored as `APT_GPG_PRIVATE_KEY` secret (base64-encoded)
- **Tool:** `reprepro` — manages `dists/`, `pool/`, and signed `InRelease` files
- **Branch:** `gh-pages` (orphan branch, separate from `main`)
- **Concurrency:** serialized via `concurrency.group: apt-repo-update` to prevent race conditions

**When adding a new Ubuntu release to the apt repo:**
1. Add a new distribution stanza to the `Configure reprepro` step in `build.yml`
2. Add the codename mapping to the `Determine target codename from tag` step

**GPG key rotation:** generate a new key, update the `APT_GPG_PRIVATE_KEY` secret, and push a new tag. The public key files on `gh-pages` are regenerated automatically each run.

## Key external URLs

- Debian source (.dsc): https://deb.debian.org/debian/pool/main/k/kodi/
- Debian snapshot archive (fetch fallback): https://snapshot.debian.org/package/kodi/
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
- **PipeWire device-enumeration deadlock** — Kodi 21.3 freezes when opening Settings → System → Audio (or on audio device change) with PipeWire active (upstream issue #27420; related crash #26212). Fixed by `patches/backports/0018-Fix-PipeWire-deadlock-in-audio-device-enumeration.patch` (backport of upstream PR #27615). Not Ubuntu-specific — it's a Kodi-21 source bug — but listed here as the symptom most users hit. **Drop this patch at Kodi 22 (Piers)**, which already contains the fix.

### Ubuntu 26.04 (Resolute)
- **Stock Kodi 21.3 lacks our backports** (`2:21.3+dfsg-1ubuntu1`, delta = ffmpeg 8 build fixes only), so we build 21.3 + backports here; Kodi 22 replaces it once it reaches Debian.
- **Built from Debian `-1.1`**, not `-1`: it adds ffmpeg 8 fixes and drops `libpostproc-dev`. `1.1~ubuntu2604N` also sorts *above* stock `1ubuntu1`, so apt prefers ours (`-1~...` would sort below).
- **`-1.1` is snapshot-only** (pool now has `-1.2`, which only adds a giflib 6 fix; 26.04 has giflib 5.2.2). `-1.2`'s signer is missing from noble's 2023 `debian-keyring`.
- **No packaging patches:** build-deps resolve as-is (ffmpeg 8.0.1, `libtag-dev` 2.2.1, Python 3.14, GCC 15). Keep `0004-ffmpeg7.patch` applied (no `quilt pop`).

### General (all releases)
- **Debian pool churn → fetch 404** — Debian drops superseded source from the live pool (e.g. `21.3+dfsg-1` was replaced by the NMU `-1.1`), so `dget` against `deb.debian.org` 404s for a pinned older revision. `fetch-source.sh` falls back to `snapshot.debian.org` for the exact pinned `.dsc`. The timestamp is per release (`SNAPSHOT_TIMESTAMP_<NODOT>` in `VERSION`) because each revision was in the archive at different times. If it ever stops serving the revision, set the `SNAPSHOT_TIMESTAMP` env var to another point when it was in the archive (any works — the `.dsc` pins component hashes, so bytes are identical).
- **`dpkg-genbuildinfo` slowness** — GH runners have a huge `/usr/local`; workflow renames it before build
- **Disk space** — workflow removes Android SDK, .NET, ghcup, PowerShell to free ~15 GB before building
- **OOM during build** — if runner runs out of RAM, fall back to `-j2`

## Refreshing patches for a new Kodi version

1. Bump `KODI_VERSION` in `VERSION`, set each `DEBIAN_REVISION_<NODOT>` / `SNAPSHOT_TIMESTAMP_<NODOT>`, and reset every `UBUNTU_BUILD_<NODOT>=1`
2. For each release, run `UBUNTU_VERSION=<ver> bash scripts/fetch-source.sh` — extracts new source into `build/` (clear `build/` between releases)
3. Try applying existing patches: `UBUNTU_VERSION=<ver> bash scripts/patch-for-ubuntu.sh`
4. If patches fail, inspect what changed in `debian/control` and `debian/patches/series` in the new version and update accordingly
5. Regenerate patches with `diff -u` against the original extracted `debian/` files
6. **Re-evaluate every `patches/backports/` patch:** check its DEP-3 `Applied-Upstream:` version against the new `KODI_VERSION`. If the new Kodi already contains the fix, delete the patch; otherwise refresh it (`quilt push`; resolve conflicts; `quilt refresh`) since the surrounding source may have moved.

## Validation checklist

For each supported Ubuntu release:
- [ ] `UBUNTU_VERSION=<ver> bash scripts/build.sh` completes end-to-end on a clean Ubuntu `<ver>` VM
- [ ] GitHub Actions workflow passes on push to `main` (all matrix entries green)
- [ ] Workflow artifacts contain `.deb` files named with the correct Ubuntu version
- [ ] Tag push triggers Release with `.deb`, `SHA256SUMS`, and per-distro build logs attached
- [ ] `sudo dpkg -i kodi-data_*.deb kodi-bin_*.deb kodi_*.deb && sudo apt -f install` succeeds on clean Ubuntu `<ver>`
- [ ] `kodi --version` shows the expected version (the Git hash and branch name vary per build, but version and codename should match, e.g. `21.3.0 ... Omega`)
- [ ] APT repository at `https://vadikmironov.github.io/kodi-ubuntu-debs/dists/<codename>/InRelease` is accessible and signed
- [ ] `sudo apt update && sudo apt install kodi` works using the apt repo on a clean Ubuntu `<ver>`
- [ ] GPG verification step in `fetch-source.sh` passes and is visible in the build log
