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
3. ~~Draft the two-partition stick layout~~ **drafted**: `notes/offline-installer-plan.md` +
   `tools/make-offline-stick.sh` (dry-run by default, `--verify`, `--write`, refuses anything
   that is not the USB stick, writes the SMBIOS-bearing `config.plist` from
   `IDENTITY_CONFIG`). **Do not run `--write`** — repartitioning `/dev/sda` needs the human's
   explicit go-ahead, and the stick is the only copy of `BaseSystem.dmg` (now also saved to
   `.downloads/recovery-backup/`).
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
   re-downloaded. **Done:** `.downloads/recovery-backup/` (image + chunklist + the
   SMBIOS-bearing `config.plist.stick-working`).
8. **Wi-Fi/BT are solved on paper**: `notes/mtk-wifi-bt.md` — both our IDs are in the match
   tables of `SimpleMtkWlan` v1.5.0 and `SimpleMtkBtFw` v1.1.0, releases downloaded and
   hash-verified into `.downloads/mtk/`. Post-install work, one boot test per change.

## Style

- Say what was measured vs assumed; quote log file names and lines as evidence.
- Never present an untested config as working: a change that needs a boot test is a
  request to the human, and the answer comes back as an `opencore-*.txt` on the stick.
