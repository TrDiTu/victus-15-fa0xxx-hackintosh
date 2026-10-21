# Offline installer (no internet during install)

Tool: github.com/corpnewt/UnPlugged + gibMacOS. UnPlugged runs **inside** the recovery
environment from a second partition; gibMacOS (Python) can download on Linux.

## Stick layout (29.3 GB stick)

```
part 1  FAT32  ~1 GB    EFI/                       ← this repo's EFI/
                        com.apple.recovery.boot/   ← BaseSystem.dmg + BaseSystem.chunklist (Sequoia 15)
part 2  ExFAT  ~15 GB   InstallAssistant.pkg       ← gibMacOS, same major version (15.x)
                        UnPlugged.command
```

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

- Where does macOS go? The NVMe is fully allocated: p1 ESP 2 GiB (Linux /boot),
  p2 Data ext4 177 GB, p3 298 GB LUKS/btrfs (Linux root). Something must shrink, or
  install to a second disk / external SSD. Shrinking the LUKS+btrfs root is destructive work.
- Keep the online recovery stick as the fallback: it boots and works today.
