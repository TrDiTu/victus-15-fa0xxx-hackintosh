# Rules for agents and automation in this repo

## Hard safety

- **Never** write to `/dev/nvme0n1` (the Linux install: omarchy_root LUKS/btrfs, `/boot` ESP,
  `/home`). No repartitioning, no `mkfs`, no `dd` against it. Ask the human first, every time.
- The USB test stick is `/dev/sda` (29.3 GB, serial `2410451035897387267`). Write it only with
  `tools/make-1401-stick.sh`, which re-checks serial, size, USB transport, mounted system paths
  and OS partition types before erasing.
- Back up `EFI/OC/config.plist` (or `cp -a EFI EFI.bak`) before editing; this EFI is the only
  configuration known to produce a display.
- Do not touch the 1401 or WhateverXe working trees under `~/repo/nullmoth/` — other people's
  repos, and 1401's AGENTS.md forbids AI-written contributions upstream.

## Working with the EFI

- `boot-args` must also be listed in `NVRAM > Delete > 7C436110-…`, or OpenCore reports
  `OCVAR: Setting NVRAM …:boot-args - ignored, exists` and silently keeps the old value.
- Keep `disable-gpu` absent from `PciRoot(0x0)/Pci(0x2,0x0)`; keep the TGL spoof keys
  (`device-id 499A0000`, `AAPL,ig-platform-id 0000499A`, framebuffer props). See
  `notes/tgl-spoof-recipe.md`.
- Do not add NVIDIA kexts to `Kernel > Add` for the installer: `NVRM` injects but
  `NVRMFB`/`NVAccel`/`NVRMAGDC` fail with "Invalid Parameter" (OCAK vtable patching).
- After editing, validate: `python3 -m p1401.efidoctor <stick-root> --report scan/Report.json`
  and `python3 -m p1401 validate <efi-dir>` (from `~/repo/nullmoth/1401`).

## Reading a boot

- Logs land on the stick as `opencore-YYYY-MM-DD-HHMMSS.txt`, 256 KiB, NUL-padded, CRLF.
  Strip `\x00`, normalise CR, then look for `EB|MBA:NV`/`MBA:OUT` (did boot-args apply),
  `Prelinked injection` (kexts), `Panic log does not exist` (no crash), `EXITBS:START` (handover).
- `EXITBS:START` is the last line of every log, success or failure — GUI success is only visible
  on screen; kernel crashes appear as `panic-*.txt` on the stick.
- Compare boots semantically: strip the leading `mm:sss mm:sss ` timestamps and diff.

## House rules

- Every configuration change goes into `HANDOFF.md` with the evidence (log name + line).
- Never present an untested change as working; say what was measured and what was assumed.
- Reference material (`.xps-reference/`) is read-only; its licence is "Thou Shalt Not Profit".
