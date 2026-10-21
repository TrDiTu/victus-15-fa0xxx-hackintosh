# Offline installer (no internet during install)

Tool: github.com/corpnewt/UnPlugged + gibMacOS. UnPlugged runs **inside** the recovery
environment from a second partition; gibMacOS (Python) can download on Linux.

## Download: done and verified (2026-10-21)

| | |
|---|---|
| Product | `142-27431` — macOS Sequoia **15.8.1 (24H32)**, catalog date 2026-09-28 17:27:52 UTC |
| Downloaded by | `gibMacOS --version 15 --no-interactive` into `.downloads/` (pane `rirt8dh`) |
| Result | gibMacOS: `Downloaded 5 of 5` / `Failed: None` |
| File | `.downloads/InstallAssistant.pkg` = **15,664,523,626 bytes** (15.66 GB) |
| SHA-256 | `e4532e3337431292a7f227fcde7eb57f7b907547e2a26b43d3aab5a3f6e44781` (computed here) |
| Also downloaded | `UpdateBrain.zip` 4,150,595 B, `com_apple_MobileAsset_MacSoftwareUpdate.plist`
1,427,972 B, `MajorOSInfo.pkg` 1,255,107 B, `InstallInfo.plist` 181 B |

**gibMacOS reports no digest.** Checked in `~/personal/gibMacOS`: `gibMacOS.py` has no
`hashlib`/md5/sha at all, and `Scripts/downloader.py: stream_to_file()` only compares the byte
count against the HTTP `Content-Length` (`ensure_size_if_present`). So the SHA-256 above is my
measurement, not gibMacOS's, and the `Downloaded 5 of 5` line is a size check only.

Integrity check that did run (`tools/verify-xar-pkg.py .downloads/InstallAssistant.pkg`):

```
XAR v1, header 28 B, TOC 4308 B compressed / 9141 B, checksum sha1
ok    TOC digest matches the copy stored in the heap (sha1 5edb8d574af56ff56cffc27160d4c998...)
ok    5 file(s) in the TOC, signature block(s): RSA
ok    SharedSupport.dmg (14924 MiB stored, archived + extracted digests match)
ok    PackageInfo / Scripts / Payload / Bom (archived + extracted digests match)
PASS: every file in the package matches its TOC digest.
```

The TOC carries an RSA signature and the certificate chain (Apple Software Update Certification
Authority → Apple Root CA), so `pkgutil --check-signature` on macOS can confirm it properly;
from Linux the chain is not verifiable, only the structure. `SharedSupport.dmg` is
15,649,233,199 of the 15,664,523,626 bytes; the rest is the small metadata members.

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

**Done 2026-10-21:** both files copied to `.downloads/recovery-backup/` (git-ignored),
`sha256 BaseSystem.dmg = c9fff24b410ae134c6be17ebd4194e0ad3d73bb839a65f8d94c93a20fe97cd1e`
(same on stick and on disk, 888,615,275 B).

## ⚠ Two config.plist identities

`EFI/OC/config.plist` in this repo has the machine identity **scrubbed** (`SystemSerialNumber
REPLACEME0001`, `MLB REPLACEMEMLB01`, zero `SystemUUID`/`ROM`) — that is what a public repo
must hold. The SMBIOS that actually booted on this laptop is the one on the current stick; it is
saved (git-ignored) as `.downloads/recovery-backup/config.plist.stick-working`,
sha256 `3c4cafaae0dd7fe1b522…`. Verified 2026-10-21 that the two configs differ **only** in:
`Kernel > Add` (the stick also lists `NVRM`/`NVRMFB`/`NVRMAGDC`/`NVAccel`, all `Enabled=false`)
and those four `PlatformInfo > Generic` identity keys. So the repo EFI is the config that booted
the recovery GUI, minus the disabled NVIDIA experiment, plus placeholders.
`tools/make-offline-stick.sh` therefore writes `IDENTITY_CONFIG` (the stick-working copy) over
the repo config, so the new stick boots with a real SMBIOS; the repo stays scrubbed.

## Steps

1. ~~Download on Linux~~ **done and verified above.**
2. Repartition the stick: `sfdisk` two MBR partitions — `type=c` (FAT32) 1 GiB at 1 MiB,
   `type=7` (exFAT) the rest. `mkfs.vfat -F 32 -n OPENCORE`, `mkfs.exfat -n UnPlugged`.
   **Scripted (drafted, never run) in `tools/make-offline-stick.sh`** — dry-run by default,
   `--verify` to check a finished stick, `--write` to do it. Needs the human's go-ahead.
3. Copy EFI + com.apple.recovery.boot to part 1; InstallAssistant.pkg + UnPlugged.command to part 2.
   `UnPlugged.command` is fetched: `.downloads/UnPlugged/` (clone of corpnewt/UnPlugged, HEAD
   `e7e0696 "Update wording"`, one 26,931 B script + README, 168 KiB total).
4. Boot recovery (this EFI boots it), Disk Utility → check the APFS container on `nvme0n1p3`,
   add/erase a volume there (not a new partition on another disk).
   **`nvme0n1` also holds the Linux root — never `diskutil eraseDisk`, never erase the device).**
   Use `diskutil list` to find the container that lives on `disk0s3` and operate on that
   container/volume only (`diskutil apfs addVolume <container> APFS macOS`, or erase just that
   volume). If in doubt, stop and ask.
5. Terminal: Sonoma+ recovery does not mount ExFAT automatically —
   `diskutil list physical`, then `/sbin/mount_exfat /dev/diskXsY /Volumes/UnPlugged`
   (`/sbin/mount_msdos` for a FAT32 volume). UnPlugged's README documents this.
6. `cd /Volumes/UnPlugged && ./UnPlugged.command`, pick the InstallAssistant, choose the
   target volume, `y`. Choose **"Fully expand InstallAssistant.pkg"**, not "extract from
   BaseSystem.dmg": our `BaseSystem.dmg` is the Sequoia one (Darwin 24), and the extract path is
   the one that needs an older recovery image alongside the package. The script then builds
   `Install macOS.app` and launches the installer — keep the Terminal open, closing it kills the
   install.
7. UnPlugged needs no network: `UnPlugged.command` contains no download code (only a URL in a
   help message), which is why this whole path works offline.

## Open questions

- ~~Where does macOS go?~~ **Answered 2026-10-21: `nvme0n1p3` (176.9 GB APFS, already
  formatted).** No shrink, no new partition on the NVMe. Remaining unknown: does that APFS
  container already hold a volume? (unverifiable from Linux without root — check in Disk Utility).
- How large will the installed system be? Apple's manifest for 24H32 says `InstallationSize`
  13,040,061,526 B (13.0 GB) and `_DownloadSize` 15,640,056,810 B (15.66 GB) — 176.9 GB is
  ample.
- Keep the online recovery stick as the fallback: it boots and works today — but see the
  BaseSystem.dmg warning above, it is the only copy of that image.
