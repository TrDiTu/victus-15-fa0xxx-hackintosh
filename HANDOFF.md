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

## Known gaps

- **Keyboard**: built-in is PS/2 — the input kexts are now in the EFI but **not yet boot-tested**.
  Immediate workaround: USB keyboard.
- **Trackpad**: ELAN I2C HID `04F3:321A`; needs `-vi2c-force-polling` (set) and likely an
  `SSDT-XPS-I2C`-style GPIO pinning of its own.
- **Wi-Fi/BT**: MediaTek — expected unusable. Use Ethernet or a supported USB dongle.
- **Acceleration**: none. Recovery runs on Apple's TGL driver without `NootedGreen`; the
  post-install accelerator path (Metal) is `src/NootedGreen` from the reference repo, built on
  macOS with Command Line Tools (`zsh install.sh`), tuned for Tahoe/RPL-P — needs adaptation.

## Next steps

1. Test the built-in keyboard/trackpad with the current EFI (one boot).
2. Build the **offline installer**: `notes/offline-installer-plan.md` (UnPlugged + gibMacOS).
3. Decide where macOS is installed — the NVMe is fully allocated (see the plan's open question).
4. After install: NootedGreen for Metal, then audio/brightness/`xe-res`-style tools.

## Do not lose

- This EFI is the only known-working display configuration. Back it up before every experiment.
- The 1401 build in `EFI-stock-1401/` plus `scan/` reproduce the stock EFI from scratch.
