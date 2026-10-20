# Security

## Reporting a problem

Please report vulnerabilities privately, not in a public issue: use
[GitHub private vulnerability reporting](https://github.com/monkey1911/omarchy-dragon-sp11/security/advisories/new)
for this repository. This is a personal hobby project; there is no bug bounty.

## Trust model

What you trust when you install from this project:

- **The maintainer** (GitHub account `monkey1911`) and **GitHub Actions** as the build
  host. Workflow actions are pinned to full commit SHAs and the build container to an
  image digest (the Arch Linux ARM `omacom/omarchy-pkg-builder` image).
- **Upstreams**, pinned in `upstream.lock` and checked, never followed blindly:
  - Omarchy (`omacom/omarchy`, `omarchy-iso`, `omarchy-pkgs`), pinned by commit; its
    `qcom-firmware-extract` and `linux-aarch64-pkgbase-shim` PKGBUILDs are built from source
  - Arch Linux ARM packages
  - Dale Whinham's Surface Pro 11 repository
    ([dwhinham/archlinux-repo](https://github.com/dwhinham/archlinux-repo)): the
    `linux-sp11` kernel and the `sp11-*` support packages are used as published. Every
    package signature is checked against the key
    `1565514CFA0B8E619ABB379861CC72A6A05CD688`, taken from that repository at a pinned
    commit (`installer/scripts/fetch-dwhinham.sh`). The installed system keeps
    `[dwhinham]` as a signed pacman repository for kernel updates.
  - [linux-surface/iptsd](https://github.com/linux-surface/iptsd), release tarball,
    checksum-pinned, rebuilt here as `iptsd-sp11`
- **The ISO itself is not signed yet.** Its `.sha256` file only shows the download is
  intact. The ISO contains no Microsoft or Qualcomm firmware; that is copied from Windows
  or Microsoft's driver packages on your own machine.

Out of scope: a compromised maintainer account, GitHub itself, and the security of the
upstream projects listed above.
