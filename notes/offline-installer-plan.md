# Offline installer (no internet during install)

Tool: github.com/corpnewt/UnPlugged + gibMacOS. UnPlugged runs **inside** the recovery
environment from a second partition; gibMacOS (Python) can download on Linux.

## Decisions (human, 2026-10-21)

- **Install target: `/dev/nvme0n1p3`** — the existing 176.9 GB APFS partition (block device
  `259:3`, UUID `49644c18-bbd1-45ec-9c07-2d14db3ff960`). It was formatted previously on purpose.
  **No shrink, no repartitioning** of the NVMe (`p1` ESP `/boot`, `p2` 298 GB LUKS→btrfs `/`,
  `/home`, `/var/log` stay as they are).
- **Installer lives on the USB stick only**, never on the internal disks.
- **No network connection is available.** Everything the install needs must be on the stick;
  nothing may be assumed downloadable at boot or install time.
- Not verifiable from Linux without root: whether `nvme0n1p3` is an APFS *container* with a
  usable volume inside, or an empty container. If it has no volume, Disk Utility in recovery
  must add one (`APFS` container exists → `+` Volume) before UnPlugged/installer can target it.
  Treat as **assumed, unmeasured**.

## Stick layout (29.3 GiB = 31,457,280,000 B = 61,440,000 sectors)

```
part 1  FAT32  1 GiB     EFI/                       ← this repo's EFI/
                         com.apple.recovery.boot/   ← BaseSystem.dmg + BaseSystem.chunklist (Sequoia 15)
part 2  ExFAT  remainder InstallAssistant.pkg       ← 15.66 GB, from gibMacOS, same major version (15.x)
                         UnPlugged.command
```

Exact geometry (draft only — **not run**):

| part | start sector | size (sectors) | size | type | fs |
|---|---|---|---|---|---|
| 1 | 2048 | 2097152 | 1 GiB | `c` (FAT32 LBA), bootable | `mkfs.vfat -F 32 -n OPENCORE` |
| 2 | 2099200 | 59340800 | 28.3 GiB | `7` (ExFAT/NTFS) | `mkfs.exfat -n UnPlugged` |

ExFAT is mandatory for part 2: FAT32 cannot hold a single file over 4 GiB and the package is
15.66 GB.

## ⚠ Before any repartitioning of `/dev/sda`

The stick is the **only copy** of the recovery image:
`com.apple.recovery.boot/BaseSystem.dmg` (888,615,275 B) + `BaseSystem.chunklist` exist nowhere
else on this machine (checked: no copy under `$HOME`, no cache in `~/.cache/1401`, not in git —
`*.dmg` is git-ignored). `tools/make-1401-stick.sh` re-downloads it from Apple (line 256), which
is impossible without a network. So: **copy both files off the stick to local disk before
`sfdisk` touches `/dev/sda`**, and re-copy them into part 1 of the new layout.
The stick also currently holds the seven `opencore-*.txt` logs — already in `logs/` in this repo.

## Steps

1. Download on Linux: `git clone https://github.com/corpnewt/gibMacOS` and fetch the
   Sequoia InstallAssistant.pkg (~13 GB). BaseSystem must be the same major version.
2. Repartition the stick: `sfdisk` two MBR partitions — `type=c` (FAT32) 1 GiB at 1 MiB,
   `type=7` (exFAT) the rest. `mkfs.vfat -F 32 -n OPENCORE`, `mkfs.exfat -n UnPlugged`.
3. Copy EFI + com.apple.recovery.boot to part 1; InstallAssistant.pkg + UnPlugged.command to part 2.
4. Boot recovery (this EFI boots it), Disk Utility → format the target **device** APFS/GUID.
5. Terminal: Sonoma+ recovery does not mount ExFAT automatically —
   `diskutil list physical`, then `/sbin/mount_exfat /dev/diskXsY /Volumes/UnPlugged`.
6. `cd /Volumes/UnPlugged && ./UnPlugged.command`, pick the InstallAssistant, choose the
   target volume, `y`. It builds Install macOS.app and starts the offline install.

## Open questions

- ~~Where does macOS go?~~ **Answered 2026-10-21: `nvme0n1p3` (176.9 GB APFS, already
  formatted).** No shrink, no new partition on the NVMe. Remaining unknown: does that APFS
  container already hold a volume? (unverifiable from Linux without root — check in Disk Utility).
- How large will the installed system be? Apple's manifest for 24H32 says `InstallationSize`
  13,040,061,526 B (13.0 GB) and `_DownloadSize` 15,640,056,810 B (15.66 GB) — 176.9 GB is
  ample.
- Keep the online recovery stick as the fallback: it boots and works today — but see the
  BaseSystem.dmg warning above, it is the only copy of that image.
