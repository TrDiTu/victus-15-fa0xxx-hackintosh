# Handoff — HP Victus 15-fa0xxx running macOS Sequoia 15 (OpenCore)

Status: **macOS recovery boots to its GUI on this laptop.** Not yet installed.
Date of state: 2026-10-21.

## Machine

| | |
|---|---|
| Board / model | HP Victus by HP Gaming Laptop 15-fa0xxx, board ID `8A4F` |
| CPU | Intel Core i7-12700H (Alder Lake-H, 20 threads) |
| iGPU | `8086:46A6` Alder Lake-P GT2 Iris Xe, PCI revision `0x0c`, drives the internal eDP panel (CMN1521) |
| dGPU | `10DE:25A2` GeForce RTX 3050 Mobile (Ampere, Optimus — HDMI is wired to it, no firmware framebuffer) |
| Wi-Fi / BT | MediaTek MT7921 `14C3:7961` — **no macOS driver** (not Intel, itlwm does not cover it) |
| Ethernet | Realtek RTL8111 `10EC:8168` — supported (`RealtekRTL8111.kext`) |
| Storage | Samsung PM9A1 NVMe (`144D:A80A`) — supported (`NVMeFix.kext`) |
| Target | macOS 15 Sequoia (Darwin 24), SMBIOS `MacBookPro16,2`, SIP `0x0A43` |

## How we got here

1. EFI built by **1401** (nullmoth) from a Linux-only workflow: `p1401.scan` → `p1401 build`
   (validated by `ocvalidate.linux`, 0 issues) → stick written by `tools/make-1401-stick.sh`
   (MBR + active FAT32, EFI verified byte-for-byte, Apple's recovery image chunk-verified).
   Build output lives in `EFI-stock-1401/`.
2. First boots: OpenCore → BaseSystem.dmg → boot.efi → kernel → recovery userspace all fine,
   but the screen froze at `IOConsoleUsers: gIOScreenLockState 3` — WindowServer had no driver.
   Seven OpenCore logs in `logs/` record each attempt (see below).
3. Root cause: the build **disabled the iGPU** (`disable-gpu = True`, because macOS has no
   Alder Lake driver) and the only NVIDIA driver exists as a post-install system extension.
   With no display driver at all, the installer UI cannot start.
4. Fix that worked: stop disabling the iGPU and present it as **Tiger Lake `0x9A49`** with a
   TGL platform-id and WhateverGreen framebuffer properties — see `notes/tgl-spoof-recipe.md`
   and `notes/stock-vs-working.diff`. Recovery now boots to its GUI.

## Log index (`logs/`)

| Log | What it tested | Result |
|---|---|---|
| `083307` | stock 1401 EFI | boots to userspace, stops at `gIOScreenLockState 3` |
| `090236` | boot-args edit without clearing NVRAM | edit ignored (`OCVAR … ignored, exists`) |
| `092740` | HDMI monitor attached | firmware GOP still 5 modes/1920×1080 → HDMI never driven at boot (it is on the dGPU) |
| `101454` | minimal args (`-v debug=0x100 keepsyms=1`) | same stop |
| `110125` | injected NullMoth NVIDIA kexts | `NVRM` injects; `NVRMFB`/`NVAccel`/`NVRMAGDC` fail OpenCore vtable patching ("Invalid Parameter") |
| `112414` | `-igfxvesa` only | no effect: iGPU was disabled by the config |
| `115518` | **iGPU enabled + TGL spoof** | ✅ recovery GUI |

Note: every OpenCore log ends at `EXITBS:START` — that is the handover to the kernel, so the
logs cannot show kernel/GUI success. Success is the screen; failures are `panic-*.txt` on the stick.

## Current state of `EFI/`

- iGPU: TGL spoof as described in `notes/tgl-spoof-recipe.md` (no `disable-gpu`).
- dGPU: unmodified (`acpi-wake-type = 1`), no NVIDIA kexts loaded.
- Kexts (25): Lilu, VirtualSMC (+ Battery/LightSensor/Processor/SuperIO), WhateverGreen,
  NVMeFix, RealtekRTL8111, RestrictEvents, BrightnessKeys, CpuTopologyRebuild, ECEnabler,
  USBToolBox + UTBDefault, XHCI-unsupported, and input: VoodooI2C (+ Services/GPIO/Input),
  VoodooI2CHID, VoodooPS2Controller (+ Keyboard/Mouse/Trackpad).
- boot-args: `-v debug=0x100 keepsyms=1 amfi=0x80 -vi2c-force-polling`
  (`boot-args` is also in `NVRAM > Delete`, otherwise OpenCore ignores config changes).
- ACPI: SSDT-SBUS/EC/GPI0/MCHC/PLUG-ALT/RTCAWAC/USB-Reset/USBX/XOSI.

## Offline installer stick (built and verified 2026-10-21)

`/dev/sda` is now the offline installer, not the old online recovery stick. Built with
`tools/make-offline-stick.sh`, verified by `./tools/make-offline-stick.sh --verify` → **PASS**
(pane `s7fsv2v`, exit 0):

```
MBR dos · p1 0x0C FAT32 OPENCORE 1 GiB · p2 0x07 ExFAT UnPlugged 28.3 GiB
p1: EFI/OC/config.plist is the identity-bearing copy, everything else matches the repo byte for byte
    com.apple.recovery.boot/BaseSystem.dmg 888,615,275 B (sha256 c9fff24b…, matches the backup) + .chunklist
p2: InstallAssistant.pkg 15,664,523,626 B, sha256 e4532e33… verified **on the stick**
    UnPlugged.command 26,931 B (corpnewt/UnPlugged e7e0696, no network code)
```

Not on the stick: the 4 `NVRM*` kexts (only ever existed on the old stick, all `Enabled=false`;
kept in `.downloads/recovery-backup/EFI-stick-working/`) and any Wi-Fi/BT kexts
(`notes/mtk-wifi-bt.md`, post-install).

The old online recovery stick is gone (repartitioned). Reconstructable: `BaseSystem.dmg`,
`chunklist`, its whole EFI (26M, 145 files) and the SMBIOS-bearing `config.plist` are in
`.downloads/recovery-backup/`.

**Next on the stick path:** BIOS Secure Boot off, F9, boot the USB → OpenCore → recovery →
Disk Utility: make an APFS volume inside `disk0s3` (**never `eraseDisk`**, `disk0` holds Linux) →
Terminal → `/sbin/mount_exfat /dev/diskXsY /Volumes/UnPlugged` →
`cd /Volumes/UnPlugged && ./UnPlugged.command` → "Fully expand InstallAssistant.pkg".

Incident worth remembering: the first `--write` (run from another pane) partitioned and formatted
fine, then died on `cp .../EFI/EFI` — `$EFI` is already this repo's `EFI/`, so the copy source had
to be `$EFI`. Fixed in `b12bec5`. Nothing was lost, because the old stick's EFI and the recovery
image had been backed up first.

## Known gaps

- **Keyboard**: ✅ **works** (reported by the human 2026-10-21, booted from the new offline stick's
  recovery GUI). The built-in keyboard is PS/2 (`AT Translated Set 2 keyboard`, `0001-0001` in
  `scan/Report.json`, `PS2K` in `scan/ACPI/DSDT.aml`), driven by `VoodooPS2Controller` +
  `VoodooPS2Keyboard`. No boot log captured yet — the report is visual.
- **Trackpad**: ✅ **works too** (same report) — ELAN I2C HID `04F3:321A` (`TPD0`/`ELAN0788` in the
  DSDT) via `VoodooI2C` + `VoodooGPIO` + `VoodooI2CHID` with `-vi2c-force-polling`. So no
  `SSDT-` GPIO pinning workaround is needed on this board.
- **UnPlugged.command "is corrupted"**: not the file — source and stick copies are identical
  (26,931 B, sha256 `92f2c3dc…`, LF, mode 755). macOS refuses to launch it; run it as
  `cd /Volumes/UnPlugged && bash UnPlugged.command` instead of double-clicking.
- **Wi-Fi/BT**: MediaTek MT7921 `14C3:7961` (Wi-Fi) / `13D3:3567` (BT USB). Two maintained
  projects now list both IDs in their match tables — `SimpleMtkWlan`/`AirportMtkWlan` v1.5.0 and
  `SimpleMtkBtFw` v1.1.0. Not boot-tested on this laptop, but no longer "expected unusable";
  releases downloaded and hash-verified. See `notes/mtk-wifi-bt.md`. Ethernet (RTL8111) works
  today and is enough for the install — which is offline anyway.
- **Acceleration**: none. Recovery runs on Apple's TGL driver without `NootedGreen`; the
  post-install accelerator path (Metal) is `src/NootedGreen` from the reference repo, built on
  macOS with Command Line Tools (`zsh install.sh`), tuned for Tahoe/RPL-P — needs adaptation.

## Next steps

1. Test the built-in keyboard/trackpad with the current EFI (one boot).
2. Build the **offline installer** stick: `notes/offline-installer-plan.md`,
   `tools/make-offline-stick.sh` (dry-run by default). The 15.8.1 (24H32) package is downloaded
   and verified; the SMBIOS-bearing `config.plist` is saved in `.downloads/recovery-backup/`.
3. Install to `/dev/nvme0n1p3` (176.9 GB APFS, already formatted) — decided by the human, no
   NVMe repartitioning.
4. After install: NootedGreen for Metal, then Wi-Fi/BT (`notes/mtk-wifi-bt.md`), audio,
   brightness, `xe-res`-style tools.

## Do not lose

- This EFI is the only known-working display configuration. Back it up before every experiment.
- The 1401 build in `EFI-stock-1401/` plus `scan/` reproduce the stock EFI from scratch.
