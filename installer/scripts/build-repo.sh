#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run INSIDE the Arch Linux ARM builder container, as root.
# Builds this repository's packages (omarchy-surface-sp11, iptsd-sp11) and two
# omarchy-pkgs PKGBUILDs, adds the signed Surface Pro 11 packages downloaded
# from [dwhinham] (fetch-dwhinham.sh), and creates the local pacman repository
# "omarchy-sp11" that omarchy-iso mounts with --local-repo.
#
# Environment (all mounts read-only except /repo):
#   SP11_PREBUILT directory holding the downloaded *.pkg.tar.* (default /prebuilt)
#   SP11_SOURCES  directories to build, one PKGBUILD directory each, in
#                 sub-directories (default /src: /src/omarchy-surface-sp11,
#                 /src/iptsd-sp11, /src/upstream/qcom-firmware-extract, /src/upstream/linux-aarch64-pkgbase-shim)
#   ARCHINSTALL_VERSION, ARCHINSTALL_SHA256  pinned archinstall (upstream.lock)
#   SP11_REPO     output repository directory (default /repo)
set -euo pipefail

prebuilt="${SP11_PREBUILT:-/prebuilt}"
src="${SP11_SOURCES:-/src}"
repo="${SP11_REPO:-/repo}"
work=/build
expected=(linux-sp11 linux-sp11-dtbs dwhinham-keyring sp11-ath12k-board sp11-audioreach-topology
	alsa-ucm-conf-sp11 sp11-grab-fw sp11-mac-fixup iptsd-sp11 omarchy-surface-sp11
	qcom-firmware-extract linux-aarch64-pkgbase-shim archinstall)

grep -q '^DisableSandbox' /etc/pacman.conf ||
	sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
pacman -Syu --noconfirm --needed base-devel git curl
sed -i "s|^PKGEXT=.*|PKGEXT='.pkg.tar.zst'|" /etc/makepkg.conf
id builder >/dev/null 2>&1 || useradd -m builder

mkdir -p "$repo" "$work/out"
chown builder:builder "$work/out"

# Build one PKGBUILD directory as the unprivileged builder user. --nodeps: the
# runtime dependencies (omarchy, linux-sp11, ...) come from other repositories
# at install time. With "deps", the PKGBUILD's depends/makedepends/checkdepends
# are installed from the ALARM repositories first (as root), for packages that
# compile something.
build_pkg() { # directory [deps]
	local dir="$1" name info
	local -a need=()
	name="$(basename "$dir")"
	[ -f "$dir/PKGBUILD" ] || { echo "build-repo: no PKGBUILD in $dir" >&2; exit 1; }
	echo "==> building $name"
	rm -rf "${work:?}/$name"
	cp -a "$dir" "$work/$name"
	chown -R builder:builder "$work/$name"
	if [ "${2:-}" = deps ]; then
		info="$(runuser -u builder -- bash -c "cd '$work/$name' && makepkg --printsrcinfo")"
		mapfile -t need < <(awk -F' = ' '$1 ~ /^\t(depends|makedepends|checkdepends)$/ { sub(/[<>=].*/, "", $2); print $2 }' <<<"$info")
		[ "${#need[@]}" = 0 ] || pacman -S --noconfirm --needed "${need[@]}"
	fi
	runuser -u builder -- env PKGDEST="$work/out" \
		bash -c "cd '$work/$name' && makepkg --nodeps --noconfirm --force --cleanbuild"
}

build_pkg "$src/omarchy-surface-sp11"
build_pkg "$src/iptsd-sp11" deps
build_pkg "$src/upstream/qcom-firmware-extract"
build_pkg "$src/upstream/linux-aarch64-pkgbase-shim"

# archinstall: the orchestrator needs 4.4; ALARM extra has 4.5 (API break).
# arch=any, so the Arch archive package is used as is, checksum-pinned.
: "${ARCHINSTALL_VERSION:?ARCHINSTALL_VERSION not set (upstream.lock)}"
: "${ARCHINSTALL_SHA256:?ARCHINSTALL_SHA256 not set (upstream.lock)}"
ai_file="archinstall-${ARCHINSTALL_VERSION}-any.pkg.tar.zst"
curl -fsSL --retry 3 -o "$work/out/$ai_file" \
	"https://archive.archlinux.org/packages/a/archinstall/$ai_file"
echo "$ARCHINSTALL_SHA256  $work/out/$ai_file" | sha256sum -c -

# Debug packages are not part of the repository.
find "$work/out" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*-debug-*' -exec cp -v {} "$repo/" \;
find "$prebuilt" -name '*.pkg.tar.*' ! -name '*.sig' ! -name '*-debug-*' -exec cp -v {} "$repo/" \;

cd "$repo"
rm -f omarchy-sp11.db* omarchy-sp11.files* omarchy.db
repo-add omarchy-sp11.db.tar.gz ./*.pkg.tar.zst
# omarchy-iso-make and build-iso.sh insist on a file named omarchy.db inside the
# --local-repo directory. Nothing reads it: the repository section is
# [omarchy-sp11] (installer/iso-patches/0005).
ln -sf omarchy-sp11.db omarchy.db

# Every package the installer needs must be listed in the database.
listing="$(tar -tzf omarchy-sp11.db.tar.gz)"
for name in "${expected[@]}"; do
	if ! grep -Eq "^$name-[0-9][^/]*/desc$" <<<"$listing"; then
		echo "build-repo: $name is missing from omarchy-sp11.db" >&2
		exit 1
	fi
done
chmod -R a+rX "$repo"
echo "build-repo: repository $repo:"
ls -l "$repo"
