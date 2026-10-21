# Next tasks — take over here

Context: read `AGENTS.md` (hard rules), `HANDOFF.md` (state + evidence), `notes/`.
Display works **only** with the Tiger Lake iGPU spoof in `EFI/OC/config.plist`
(`notes/tgl-spoof-recipe.md`). macOS is not installed yet.

## Live job already running (do not restart it)

The full installer is downloading right now in another Kero pane (pane `rirt8dh`,
parent session), not in this session:

```
macOS Sequoia 15.8.1 (24H32), InstallAssistant.pkg 15.66 GB
source : gibMacOS --version 15 --no-interactive  (~/personal/gibMacOS)
target : .downloads/            (git-ignored)
log    : .downloads/gibmacos.log
```

Check progress with `kero read rirt8dh -n 20` or
`tail -c 200 .downloads/gibmacos.log`; wait for it with
`kero wait rirt8dh --exit`. When it finishes, verify the `.pkg` size/digest gibMacOS
printed and record it in `notes/offline-installer-plan.md`.

## Task queue

1. **Verify the download** (above) and note the exact version/build in
   `notes/offline-installer-plan.md`.
2. **Fetch UnPlugged** (`github.com/corpnewt/UnPlugged`, `UnPlugged.command`) into
   `.downloads/` and list it in the plan.
3. **Draft the two-partition stick layout** in `notes/offline-installer-plan.md`
   with exact commands: MBR, part 1 FAT32 1 GiB (`type=c`, EFI + `com.apple.recovery.boot`),
   part 2 ExFAT rest (`type=7`), `mkfs.vfat -F 32 -n OPENCORE`, `mkfs.exfat -n UnPlugged`.
   **Do not run them** — repartitioning `/dev/sda` needs the human's explicit go-ahead.
4. **Keyboard/trackpad test needs the human.** `EFI/` now carries VoodooPS2Controller
   (+Keyboard/Mouse/Trackpad), VoodooI2C (+Services/GPIO/Input), VoodooI2CHID and
   `-vi2c-force-polling`, but it has never been booted. Ask for the result; if the built-in
   keyboard still does not type, iterate: check PS/2 presence in the DSDT, try
   `VoodooPS2Keyboard` alone, then add `SSDT-` GPIO pinning for the ELAN `04F3:321A` trackpad.
   USB keyboard is the interim workaround.
5. **Where does macOS go?** **Answered by the human 2026-10-21:** the existing 176.9 GB APFS
   partition `/dev/nvme0n1p3` (UUID `49644c18-…`) — already formatted on purpose. No shrink, no
   new partition, nothing written to the NVMe by us. The installer media stays on the USB stick
   only, and **there is no network available**, so everything must be on the stick. See
   `notes/offline-installer-plan.md`.
6. Every change: update `HANDOFF.md`, commit, `git push` (public repo, serials are
   placeholders — never commit real ones).
7. **Before repartitioning `/dev/sda`:** it holds the only copy of Apple's recovery image
   (`BaseSystem.dmg`, 888 MB). Copy it to local disk first — with no network it cannot be
   re-downloaded.

## Style

- Say what was measured vs assumed; quote log file names and lines as evidence.
- Never present an untested config as working: a change that needs a boot test is a
  request to the human, and the answer comes back as an `opencore-*.txt` on the stick.
