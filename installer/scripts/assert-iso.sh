#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Assertions on a freshly built installer ISO (CI, and runnable locally).
#   - the live UKI omarchy-live.efi and the linux-sp11 kernel/initramfs are in the ISO
#   - the live root carries linux-sp11 modules, its denali device trees and our
#     drop-ins, and no other kernel
#   - the offline mirror holds every package the Surface Pro 11 profile installs
#   - no Microsoft firmware anywhere: no qcom/<soc>/microsoft/ or .../Denali/
#     path in the ISO tree, the live root, or any package of the offline mirror
#     (the AudioReach topology qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin
#     is an open file and is fine)
# Adapted from omarchy-dragon-sl7 (qBitnaut, MIT).
#
# usage: assert-iso.sh ISO [WORKDIR]
#   needs xorriso, squashfs-tools (unsquashfs) and libarchive-tools (bsdtar);
#   WORKDIR (default: a temp dir, removed at the end) needs the ISO's size free.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

iso="${1:?usage: assert-iso.sh ISO [WORKDIR]}"
[ -f "$iso" ] || die "no such ISO: $iso"
for t in xorriso unsquashfs bsdtar; do
	command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"
done

if [ -n "${2:-}" ]; then
	work="$2"
	mkdir -p "$work"
else
	work="$(mktemp -d)"
	trap 'rm -rf "${work:?}"' EXIT
fi

# Case-insensitive; matches a vendor directory named microsoft under qcom/, or a
# Denali/Romulus directory. Does not match a *-tplg.bin file name.
forbidden='qcom/[^/]+/microsoft(/|$)|qcom/.*/microsoft/|/(denali|romulus)/'
fail=0
bad() {
	echo "FAIL: $*" >&2
	fail=1
}

# --- ISO tree ---------------------------------------------------------------
info "ISO tree"
xorriso -indev "$iso" -find / -type f >"$work/iso-files.txt" 2>"$work/xorriso.log" ||
	{ tail -n 20 "$work/xorriso.log" >&2; die "xorriso could not read $iso"; }
for f in /arch/boot/aarch64/omarchy-live.efi /arch/boot/aarch64/vmlinuz-linux-sp11 \
	/arch/boot/aarch64/initramfs-linux-sp11.img /arch/aarch64/airootfs.sfs; do
	grep -Fxq "'$f'" "$work/iso-files.txt" || bad "ISO has no $f"
done
if grep -Fq "vmlinuz-linux-aarch64'" "$work/iso-files.txt"; then
	bad "ISO carries the stock linux-aarch64 kernel as its live kernel"
fi
if grep -Eiq "$forbidden" "$work/iso-files.txt"; then
	grep -Ei "$forbidden" "$work/iso-files.txt" >&2
	bad "Microsoft firmware path in the ISO tree"
fi

# --- live root --------------------------------------------------------------
info "live root (airootfs.sfs)"
xorriso -osirrox on -indev "$iso" -extract /arch/aarch64/airootfs.sfs "$work/airootfs.sfs" \
	>>"$work/xorriso.log" 2>&1 || die "could not extract airootfs.sfs"
unsquashfs -l "$work/airootfs.sfs" >"$work/sfs-files.txt" || die "unsquashfs -l failed"
if grep -Eiq "$forbidden" "$work/sfs-files.txt"; then
	grep -Ei "$forbidden" "$work/sfs-files.txt" >&2
	bad "Microsoft firmware path in the live root"
fi
for f in etc/mkinitcpio.conf.d/zzz-sp11-live.conf usr/share/omarchy-iso/platforms.json; do
	grep -Fxq "squashfs-root/$f" "$work/sfs-files.txt" || bad "live root has no /$f"
done
grep -Fxq 'squashfs-root/etc/vconsole.conf' "$work/sfs-files.txt" || bad "live root has no /etc/vconsole.conf"
grep -Eq '^squashfs-root/usr/lib/modules/[^/]*sp11[^/]*/vmlinuz$' "$work/sfs-files.txt" ||
	bad "live root has no linux-sp11 kernel under /usr/lib/modules"
grep -Eq '^squashfs-root/usr/lib/modules/[^/]*sp11[^/]*/dtb/qcom/x1e80100-microsoft-denali-oled\.dtb$' "$work/sfs-files.txt" ||
	bad "live root has no linux-sp11 denali device tree (linux-sp11-dtbs)"
if grep -E '^squashfs-root/usr/lib/modules/[^/]+/vmlinuz$' "$work/sfs-files.txt" | grep -v sp11; then
	bad "live root carries another kernel besides linux-sp11"
fi

# --- offline mirror ---------------------------------------------------------
info "offline mirror (every package)"
mirror="var/cache/omarchy/mirror/offline"
unsquashfs -no-progress -d "$work/mirror" "$work/airootfs.sfs" "$mirror" >"$work/unsquashfs.log" 2>&1 ||
	{ tail -n 20 "$work/unsquashfs.log" >&2; die "could not extract the offline mirror"; }
mdir="$work/mirror/$mirror"
for p in linux-sp11 linux-sp11-dtbs dwhinham-keyring omarchy-surface-sp11 iptsd-sp11 sp11-ath12k-board \
	sp11-audioreach-topology alsa-ucm-conf-sp11 sp11-grab-fw sp11-mac-fixup linux-firmware-qcom \
	qcom-firmware-extract linux-aarch64-pkgbase-shim; do
	found="$(find "$mdir" -maxdepth 1 -name "$p-[0-9]*.pkg.tar.*" ! -name '*.sig')"
	[ -n "$found" ] || bad "offline mirror has no $p"
done
# omarchy-iso's orchestrator is written against archinstall 4.4 (4.5 dropped sanity_check(offline=)).
ai="$(find "$mdir" -maxdepth 1 -name 'archinstall-[0-9]*.pkg.tar.*' ! -name '*.sig' -printf '%f\n')"
case "$ai" in
archinstall-4.4-*) ;;
*) bad "offline mirror archinstall is '$ai', the orchestrator needs 4.4" ;;
esac
n=0
: >"$work/pkg-files.txt"
while IFS= read -r -d '' pkg; do
	n=$((n + 1))
	bsdtar -tf "$pkg" | sed "s#^#$(basename "$pkg"): #" >>"$work/pkg-files.txt" ||
		die "cannot list $pkg"
done < <(find "$mdir" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -print0)
echo "    scanned $n packages"
[ "$n" -gt 100 ] || bad "offline mirror has only $n packages"
if grep -Eiq "$forbidden" "$work/pkg-files.txt"; then
	grep -Ei "$forbidden" "$work/pkg-files.txt" >&2
	bad "Microsoft firmware path inside an offline-mirror package"
fi

[ "$fail" = 0 ] || die "ISO assertions failed"
info "ISO assertions passed: $(basename "$iso")"
