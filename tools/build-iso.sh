#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the Surface Pro 11 Omarchy installer ISO on your own machine, the same
# way .github/workflows/installer-iso.yml does on GitHub's ARM runners.
#
# usage: tools/build-iso.sh [WORKDIR]
#   WORKDIR  scratch directory (default: ./build). Needs about 30 GB free; put
#            it on an SSD, not an SD card. The ISO ends up in WORKDIR/out/.
#
# Needs: docker (able to run --privileged containers), git, curl, gpg, tar.
# Optional, for the final content check: xorriso, unsquashfs, bsdtar.
#
# Runs natively on an aarch64 machine (Raspberry Pi 5, an ARM laptop or VM).
# On x86_64 it runs the aarch64 containers through QEMU user emulation, which
# works but is several times slower; register it once with
#   docker run --privileged --rm tonistiigi/binfmt --install arm64
# (or install qemu-user-static + binfmt support from your distribution).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
scripts="$root/installer/scripts"
# shellcheck source=../installer/scripts/lib.sh
source "$scripts/lib.sh"
load_lock
export ARCHINSTALL_VERSION ARCHINSTALL_SHA256

work="$(mkdir -p "${1:-$root/build}" && cd "${1:-$root/build}" && pwd)"
# Arch Linux ARM build environment, the same pinned image as CI.
builder_image=ghcr.io/omacom/omarchy-pkg-builder@sha256:a0cedbe8fb2f15aa34217ddd8a74a5e12003dc442f16f1825ab2b9e023488a63

for t in docker git curl gpg tar; do
	command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"
done
docker info >/dev/null 2>&1 || die "docker is not running, or this user may not use it"

case "$(uname -m)" in
aarch64 | arm64) info "native aarch64 build" ;;
*)
	if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
		die "this is $(uname -m) and aarch64 emulation is not registered; run:
  docker run --privileged --rm tonistiigi/binfmt --install arm64"
	fi
	info "$(uname -m) host: aarch64 containers run under QEMU (slow; expect hours)"
	;;
esac

avail_gb=$(($(df -Pk "$work" | awk 'NR == 2 { print $4 }') / 1024 / 1024))
((avail_gb >= 30)) || info "warning: only ${avail_gb} GB free in $work; the build needs about 30 GB"

# 1. Pinned upstream sources.
"$scripts/fetch-upstreams.sh" "$work" omarchy-iso omarchy omarchy-pkgs
"$scripts/export-pkgbuilds.sh" "$work/omarchy-pkgs" "$work/upstream-pkgbuilds"

# 2. Signed Surface Pro 11 packages from [dwhinham].
rm -rf "$work/dl"
"$scripts/fetch-dwhinham.sh" "$work/dl"

# 3. Local package repository [omarchy-sp11].
rm -rf "$work/repo"
mkdir -p "$work/repo"
info "building packages and the [omarchy-sp11] repository"
docker run --rm --platform linux/arm64 --user 0 \
	-v "$scripts:/scripts:ro" \
	-v "$root/pkgs/omarchy-surface-sp11:/src/omarchy-surface-sp11:ro" \
	-v "$root/pkgs/iptsd-sp11:/src/iptsd-sp11:ro" \
	-v "$work/upstream-pkgbuilds:/src/upstream:ro" \
	-v "$work/dl:/prebuilt:ro" \
	-v "$work/repo:/repo" \
	-e ARCHINSTALL_VERSION -e ARCHINSTALL_SHA256 \
	"$builder_image" \
	bash /scripts/build-repo.sh
"$scripts/guard-artifacts.sh" "$work/repo"
(
	cd "$work/repo"
	ln -sf omarchy-sp11.db.tar.gz omarchy-sp11.db
	ln -sf omarchy-sp11.files.tar.gz omarchy-sp11.files
	ln -sf omarchy-sp11.db omarchy.db
)

# 4. Patch omarchy-iso and build.
"$scripts/apply-iso-patches.sh" "$work/omarchy-iso"
info "building the ISO (omarchy-iso-make)"
start=$(date +%s)
(
	cd "$work/omarchy-iso"
	./bin/omarchy-iso-make --arch aarch64 --media-target aarch64/snapdragon --edge \
		--local-source ../omarchy ../omarchy-pkgs --local-repo ../repo \
		--keep-pkg-cache --no-boot-offer
)
info "ISO build took $(($(date +%s) - start)) s"

shopt -s nullglob
isos=("$work"/omarchy-iso/release/*.iso)
((${#isos[@]} == 1)) || die "expected exactly one ISO in $work/omarchy-iso/release, got ${#isos[@]}"
mkdir -p "$work/out"
mv -f "${isos[0]}" "$work/out/"
iso="$work/out/$(basename "${isos[0]}")"
(cd "$work/out" && sha256sum "$(basename "$iso")" | tee "$(basename "$iso").sha256")

# 5. Content check, when the tools are there.
if command -v xorriso >/dev/null && command -v unsquashfs >/dev/null && command -v bsdtar >/dev/null; then
	"$scripts/assert-iso.sh" "$iso" "$work/assert"
	rm -rf "$work/assert"
else
	info "skipping the ISO content check (needs xorriso, unsquashfs, bsdtar)"
fi
info "done: $iso"
