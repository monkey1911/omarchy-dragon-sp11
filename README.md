# omarchy-dragon-sp11

**Omarchy for the Microsoft Surface Pro 11 (Snapdragon X)**

> Unofficial personal port. Not affiliated with or endorsed by Omarchy/Basecamp,
> Microsoft or Qualcomm, and not part of the Surface Pro 11 archiso project it builds on.

This repository is a thin layer on top of three things, and it only works because of them:

- **[omacom/omarchy](https://github.com/omacom/omarchy) and
  [omarchy-iso](https://github.com/omacom/omarchy-iso)** (the `dragon` ARM64 branches),
  which already know how to install Omarchy on Snapdragon laptops.
- **[dwhinham/archiso-aarch64-sp11](https://github.com/dwhinham/archiso-aarch64-sp11)
  and [dwhinham/archlinux-repo](https://github.com/dwhinham/archlinux-repo)** by Dale
  Whinham and contributors: the `linux-sp11` kernel, the Surface Pro 11 device trees,
  Wi-Fi, audio and firmware tooling, and the upstream kernel work behind them. This port
  uses their signed packages as published. **Please do not report problems with this port
  on their issue tracker.** If something also fails on their own ISO, report it there;
  otherwise it is this port's problem.
- **[qBitnaut/omarchy-dragon-sl7](https://github.com/qBitnaut/omarchy-dragon-sl7)**
  (MIT), the Omarchy port for the Surface Laptop 7 that this repository was forked from.
  The installer patch approach, the build pipeline and much of the add-on package are
  adapted from it.

## Status

**Untested on hardware.** The ISO pipeline builds, but nobody has booted it on a Surface
Pro 11 yet. Hardware support is whatever `linux-sp11` provides; see the
[Surface Pro 11 archiso status table](https://github.com/dwhinham/archiso-aarch64-sp11#whats-working)
(touchscreen and pen, Wi-Fi, audio, suspend work there; cameras and the 5G modem do not).

Known gaps of this port:

- **OLED (Snapdragon X Elite) model only.** systemd selects the OLED device tree for every
  Surface Pro 11, so the LCD (X Plus) model would boot with the wrong one. Not handled yet.
- **No online package repository of its own yet.** `linux-sp11` and the `sp11-*` packages
  update from `[dwhinham]` with `omarchy update`; `omarchy-surface-sp11` and `iptsd-sp11`
  only change when you reinstall them from a newer ISO.

## What the port does

| Piece | What it is |
|---|---|
| `installer/iso-patches/` | 7 small patches to `omarchy-iso`: a Surface Pro 11 entry in `platforms.json` (matched by DMI `Microsoft Surface Pro, 11th Edition`), `linux-sp11` as the live kernel with its device trees, the Flex Keyboard modules in the live initramfs, the local `[omarchy-sp11]` repository, and a larger console font |
| `pkgs/omarchy-surface-sp11` | the add-on package installed on the target: initramfs modules, device trees in the boot image, `linux-sp11` first in the Limine menu, the `[dwhinham]` repository for kernel updates, the `qcom_battmgr` blacklist, a speaker-safety audio rule, and `omarchy-sp11-firmware`. Details in its [README](pkgs/omarchy-surface-sp11/README.md) |
| `pkgs/iptsd-sp11` | upstream iptsd 3.1.0 (touchscreen and pen) rebuilt for Arch Linux ARM |
| `installer/scripts/` | the build pipeline: pinned upstreams, signature-checked download from `[dwhinham]`, package repository, ISO content checks |
| `tools/build-iso.sh` | the same build on your own machine |
| `upstream.lock` | every pinned input |

The installed system boots `linux-sp11` from a unified kernel image that carries the
Surface Pro 11 device tree. The stock `linux-aarch64` kernel stays installed as a second
(rescue) boot entry.

## Before you install

> **A full-disk install wipes the internal SSD, including Windows.** To keep Windows, use the
> installer's *Free space install* (see [Dual boot](#dual-boot)). Either way, do these first:

- [ ] Back up everything you want to keep.
- [ ] Install all Windows and Surface firmware updates. Surface firmware only updates from
      Windows.
- [ ] **Turn off BitLocker / Device encryption** (Settings > Privacy & security > Device
      encryption, or `manage-bde -off C:` as administrator) and wait for decryption to
      finish. The installer copies the GPU and DSP firmware from Windows just before it
      wipes the disk, and it cannot read an encrypted partition. If you skip this, use
      `sudo omarchy-sp11-firmware` after installing (needs Wi-Fi).
- [ ] Write down the Wi-Fi and Bluetooth MAC addresses (`getmac /v` and the Bluetooth
      adapter's properties in Device Manager, or `ipconfig /all`). Linux cannot read
      them, and Bluetooth does not work without them.
- [ ] Optionally make a Surface recovery USB from Microsoft's recovery image page, so
      Windows can be put back later.
- [ ] Turn **Secure Boot off**: hold Volume Up while powering on, Security > Secure Boot >
      None.

## Get the ISO

The ISO is built by GitHub Actions on this repository
(`.github/workflows/installer-iso.yml`, about an hour on GitHub's ARM runners):

1. On a fork, enable Actions once (the Actions tab, "I understand my workflows").
2. A push that touches `installer/`, `pkgs/`, `tools/` or `upstream.lock` starts a build;
   so does "Run workflow" on the installer-iso workflow page.
3. Download it from the finished run's **omarchy-sp11-installer-iso** artifact (any
   branch, kept 14 days), or from the `installer-latest` release (builds of `main` only).
   The release splits the ISO into parts because it is over 2 GiB:
   ```
   cat NAME.iso.part-* > NAME.iso
   sha256sum -c NAME.iso.sha256
   ```

To build it yourself instead, see [Building locally](#building-locally).

## Install

These steps follow the
[Surface Pro 11 archiso boot instructions](https://github.com/dwhinham/archiso-aarch64-sp11#boot-instructions),
which are precise for a reason:

1. **Write the ISO** to a USB stick (16 GB or more) as a raw image:
   `sudo dd bs=4M if=NAME.iso of=/dev/sdX conv=fsync oflag=direct status=progress`, or
   balenaEtcher on Windows. Do not use Ventoy, or Rufus in ISO mode.
2. **Boot it from the UEFI menu**: hold Volume Up while the Surface restarts, tap
   *Boot configuration*, and swipe left on *USB Storage* to boot it immediately. Don't rely
   on boot order alone.
3. **Wait.** The screen can stay black for a couple of minutes while the image unpacks.
4. Run the Omarchy installer. Its log should show `hardware profile: Microsoft Surface Pro 11`.
   If it doesn't, stop: the Surface Pro 11 packages would not be installed. Check
   `cat /sys/class/dmi/id/product_name` and report it.
5. Pick the internal NVMe, choose *Full disk install* or *Free space install*, and set the
   disk encryption passphrase. The Flex Keyboard works
   at the unlock prompt if it is attached (the modules are in the initramfs; untested).

## Dual boot

Omarchy's installer can install beside Windows instead of wiping it:

1. In Windows, turn BitLocker off and let it finish decrypting. The installer refuses a
   disk with BitLocker on; suspending it is not enough.
2. Shrink the Windows partition in Disk Management (or `diskmgmt.msc`) and leave the space
   **unallocated**. Omarchy needs at least 32 GB, plus 2 GB for its own EFI partition.
3. In the installer, pick *Free space install (alongside existing data)*. It creates its own
   EFI partition and leaves the Windows one untouched.
4. Choose the system at power-on from the Surface UEFI menu (hold Volume Up, *Boot
   configuration*).

A dual boot also keeps the firmware source at hand: `sudo qcom-firmware-extract --install`
re-reads it from the (decrypted) Windows partition at any time.

## After the first boot

- **Firmware.** If the installer could not copy it from Windows, connect to Wi-Fi and run
  `sudo omarchy-sp11-firmware`, then reboot. `omarchy-sp11-firmware --status` lists what is
  missing.
- **MAC addresses.** Put them in `/etc/sp11-mac.conf` (`WIFI_MAC=` and `BT_MAC=`) and
  reboot.
- **Updates.** `omarchy update` updates `linux-sp11` from the `[dwhinham]` repository.
  `omarchy-sp11-repo-ensure --check` shows whether that repository is configured.
- **If it does not boot**, pick the `linux-aarch64` entry in the Limine menu.

## Building locally

`tools/build-iso.sh [WORKDIR]` runs the whole pipeline with Docker:

- **Native ARM64** (a Raspberry Pi 5 with 8 GB, an ARM laptop or VM): runs as is. Use an
  SSD for `WORKDIR`, not an SD card; it needs about 30 GB.
- **x86_64**: register ARM64 emulation once with
  `docker run --privileged --rm tonistiigi/binfmt --install arm64`, then run the script.
  It works, several times slower.

The ISO lands in `WORKDIR/out/`.

## License

MIT for this repository's own files (see `LICENSE`; portions copyright qBitnaut). The
packages it downloads keep their own licenses: `linux-sp11` is GPL-2.0, iptsd is
GPL-2.0-or-later, and Dale Whinham's packaging is in
[dwhinham/archlinux-repo](https://github.com/dwhinham/archlinux-repo). No Microsoft or
Qualcomm firmware is included anywhere in this repository or its ISO.
