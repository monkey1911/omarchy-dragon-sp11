# omarchy-surface-sp11

Omarchy add-on package for the Microsoft Surface Pro 11 (Snapdragon X Elite/Plus,
device tree `x1e80100-microsoft-denali-oled`) on Arch Linux ARM.

It is made only of files, pacman hooks and drop-ins, depends on `omarchy`,
`linux-sp11`, `linux-sp11-dtbs`, `iptsd-sp11` and `linux-firmware-qcom`, and needs
no change to Omarchy. License: MIT (see `LICENSE`).

**No firmware is in this package.** The Microsoft/Qualcomm files are copied from
Windows by the installer (`qcom-firmware-extract`), or fetched afterwards with
`sudo omarchy-sp11-firmware`.

## Credits

- The structure, and the files marked "Adapted from omarchy-surface-sl7", come from
  [qBitnaut/omarchy-dragon-sl7](https://github.com/qBitnaut/omarchy-dragon-sl7) (MIT).
- The kernel (`linux-sp11`), the Surface Pro 11 support packages (`sp11-*`,
  `alsa-ucm-conf-sp11`) and almost everything known about running Linux on this
  machine come from Dale Whinham and the contributors of
  [dwhinham/archiso-aarch64-sp11](https://github.com/dwhinham/archiso-aarch64-sp11)
  and [dwhinham/archlinux-repo](https://github.com/dwhinham/archlinux-repo). This
  package only consumes their packages; please don't report problems with this
  Omarchy port to their issue tracker.

## What it installs

| # | What | Files |
|---|---|---|
| 1 | initramfs modules (Flex Keyboard, display) and GPU firmware hook | `/etc/mkinitcpio.conf.d/zz-omarchy-surface-sp11.conf`, `/usr/lib/initcpio/install/sp11-firmware` |
| 2 | neutralise Omarchy's x86 `fix-surface-keyboard.sh` module list | `70-omarchy-surface-sp11-keyboard.hook`, `/usr/lib/omarchy-surface-sp11/neutralize-surface-keyboard`, `omarchy-surface-sp11-neutralize.service` |
| 3 | `console=tty0`, `ENABLE_UKI=yes`, device trees in the UKI, `linux-sp11` first in `BOOT_ORDER` | `/etc/limine-entry-tool.d/omarchy-surface-sp11.conf`, `85-omarchy-surface-sp11-dtbs.hook`, `update-uki-dtbs`, `set-boot-order` |
| 4 | Surface (SAM) battery driver instead of `qcom_battmgr` | `/usr/lib/modprobe.d/omarchy-surface-sp11.conf` |
| 5 | no Pro Audio profile on the speaker card | WirePlumber `50-omarchy-surface-sp11.conf` and `guard-pro-audio.lua` |
| 6 | firmware helper | `/usr/bin/omarchy-sp11-firmware` |
| 7 | `[dwhinham]` repository, kept in `/etc/pacman.conf` so `linux-sp11` updates arrive with `omarchy update` | `/etc/pacman.d/omarchy-sp11-dwhinham.conf`, `/usr/bin/omarchy-sp11-repo-ensure`, `80-omarchy-sp11-repo.hook`, `omarchy-sp11-repo.service` |

### Notes

- **Initramfs.** Omarchy's `fix-surface-keyboard.sh` matches every Microsoft machine and
  writes `MODULES=(... intel_lpss_pci 8250_dw)`, which breaks mkinitcpio on arm64. The
  drop-in removes those names, makes every remaining module optional (the stock
  `linux-aarch64` rescue kernel lacks the Surface modules), and the hook/service move the
  generated file aside.
- **Device trees.** `linux-sp11-dtbs` installs its trees in
  `/usr/lib/modules/<kver>/dtb/qcom`; Omarchy builds the UKI from `/boot/dtbs/qcom`.
  `update-uki-dtbs` copies the denali trees there (keeping the stock file once as
  `.alarm-orig`) and writes the `DeviceTreeAuto` block in `/etc/kernel/uki.conf` with the
  same markers as Omarchy's `qualcomm/dtb-uki.sh`. systemd-stub picks the tree from SMBIOS:
  systemd's hardware-ID table maps the Surface Pro 11 to `microsoft,denali-oled`.
- **LCD models.** The Snapdragon X Plus (LCD) Surface Pro 11 has the same SMBIOS identity,
  so it would also get the OLED tree. Not handled yet; `update-uki-dtbs` warns.
- **Battery.** Blacklisting `qcom_battmgr` follows the Surface Pro 11 archiso's
  post-install advice. To undo it, create `/etc/modprobe.d/omarchy-surface-sp11.conf`
  with only a comment in it and rebuild (`sudo limine-mkinitcpio`).
- **Wi-Fi/Bluetooth MAC.** `sp11-mac-fixup` (installed alongside) applies the addresses in
  `/etc/sp11-mac.conf`. They cannot be read on Linux; copy them from Windows.
- **Repository.** `[dwhinham]` is only added once `dwhinham-keyring` has made the key
  trusted. Opt out with `sudo touch /etc/pacman.d/omarchy-sp11.disabled`.
