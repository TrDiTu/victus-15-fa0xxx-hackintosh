# HP Victus 15-fa0xxx — macOS Sequoia (OpenCore)

Working notes, EFI and handoff for running macOS 15 Sequoia on an HP Victus 15-fa0xxx
(board 8A4F, i7-12700H, Alder Lake-P Iris Xe + RTX 3050 Mobile).

- EFI/ — the **working** OpenCore EFI (Tiger Lake iGPU spoof; boots Apple's recovery to the GUI)
- EFI-stock-1401/ — the unmodified 1401 build for this machine, kept for diffing
- notes/stock-vs-working.diff — the exact 14 keys that made the display work
- scan/ — Report.json + ACPI dump the EFI was built from
- logs/ — OpenCore logs, one per boot attempt (the display saga in order)
- tools/make-1401-stick.sh — writes the installer stick from Linux
- .xps-reference/ — reference hackintosh for the same GPU family (git-ignored)

Read HANDOFF.md first; rules for agents/automation are in AGENTS.md.

## Serial numbers were removed

`PlatformInfo.Generic` here holds placeholders (`REPLACEME0001` / `REPLACEMEMLB01` / zero UUID and ROM),
and the OpenCore logs were scrubbed the same way. Do not publish real serials: they identify a
machine to Apple. Generate your own before booting — e.g. rebuild with 1401 (`p1401 build`) or use
`PlatformInfo > Generic` with your own values. `notes/` explains what the rest of the config does.
