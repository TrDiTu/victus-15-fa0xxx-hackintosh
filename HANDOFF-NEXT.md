# Next tasks — take over here

Context: read `AGENTS.md` (hard rules), `HANDOFF.md` (state + evidence), `notes/`.
Display works **only** with the Tiger Lake iGPU spoof in `EFI/OC/config.plist`
(`notes/tgl-spoof-recipe.md`). macOS is not installed yet.

## Live job already running (do not restart it)

~~The full installer is downloading right now~~ — **done 2026-10-21 19:39**: gibMacOS reported
`Downloaded 5 of 5` / `Failed: None`. `.downloads/InstallAssistant.pkg` =
15,664,523,626 B, sha256 `e4532e3337431292a7f227fcde7eb57f7b907547e2a26b43d3aab5a3f6e44781`,
XAR TOC + all 5 members digest-verified by `tools/verify-xar-pkg.py`. Details in
`notes/offline-installer-plan.md`.

## Task queue

1. ~~Verify the download~~ **done** (see above); `EXPECT_PKG_SHA256` for the stick script is that
   sha256.
2. **Fetch UnPlugged** (`github.com/corpnewt/UnPlugged`, `UnPlugged.command`) into
   `.downloads/UnPlugged/` and list it in the plan.
3. ~~Draft the two-partition stick layout~~ **done and built**: `tools/make-offline-stick.sh`
   produced `/dev/sda` (MBR, 1 GiB FAT32 `OPENCORE` + 28.3 GiB ExFAT `UnPlugged`) and
   `--verify` confirms it (package sha256 re-checked **on the stick**, EFI byte-for-byte, recovery
   image against the backup). Details and the `EFI/EFI` copy bug that broke the first `--write`
   are in `HANDOFF.md`. The old 1401 stick's EFI + recovery image are backed up in
   `.downloads/recovery-backup/`.
4. ~~Keyboard/trackpad test~~ **PASSED, reported by the human 2026-10-21**: the built-in PS/2
   keyboard and the ELAN I2C trackpad both work in the recovery GUI from the new offline stick.
   So `VoodooPS2Controller` + `VoodooI2C`/`VoodooGPIO`/`VoodooI2CHID` with
   `-vi2c-force-polling` is the right set; no `SSDT-` GPIO pinning needed. Recorded in
   `HANDOFF.md`. No OpenCore log captured for that boot yet — worth grabbing from the stick
   later for the record.
5. **Where does macOS go?** **Answered by the human 2026-10-21:** the existing 176.9 GB APFS
   partition `/dev/nvme0n1p3` (UUID `49644c18-…`) — already formatted on purpose. No shrink, no
   new partition, nothing written to the NVMe by us. The installer media stays on the USB stick
   only, and **there is no network available**, so everything must be on the stick. See
   `notes/offline-installer-plan.md`.
6. Every change: update `HANDOFF.md`, commit, `git push` (public repo, serials are
   placeholders — never commit real ones).
7. **Before repartitioning `/dev/sda`:** it holds the only copy of Apple's recovery image
   (`BaseSystem.dmg`, 888 MB). Copy it to local disk first — with no network it cannot be
   re-downloaded. **Done:** `.downloads/recovery-backup/` (image + chunklist + the
   SMBIOS-bearing `config.plist.stick-working`).
8. **Wi-Fi/BT are solved on paper**: `notes/mtk-wifi-bt.md` — both our IDs are in the match
   tables of `SimpleMtkWlan` v1.5.0 and `SimpleMtkBtFw` v1.1.0, releases downloaded and
   hash-verified into `.downloads/mtk/`. Post-install work, one boot test per change.

## Style

- Say what was measured vs assumed; quote log file names and lines as evidence.
- Never present an untested config as working: a change that needs a boot test is a
  request to the human, and the answer comes back as an `opencore-*.txt` on the stick.
