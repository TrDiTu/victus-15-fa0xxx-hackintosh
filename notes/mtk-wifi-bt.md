# MediaTek MT7921 Wi-Fi and Bluetooth on macOS

The handoff used to say "MediaTek MT7921 — **no macOS driver** (not Intel, itlwm does not cover
it)". That is out of date: two maintained projects now target exactly this card, and **our PCI
and USB IDs are both in their match tables**. Nothing here has been booted on this laptop yet.

## Our hardware (measured)

| | |
|---|---|
| Wi-Fi | `lspci -nn` → `04:00.0 Network controller: MEDIATEK Corp. MT7921 802.11ax PCIe Wireless Network Adapter [Filogic 330] [14c3:7961]`; `scan/Report.json` → `14C3-7961`, subsystem `46821A3B` |
| Bluetooth | same M.2 card, USB function; `scan/Report.json` → `IMC Networks Wireless_Device`, `13D3-3567` |

`13D3` is IMC/AzureWave's vendor ID for the module — **not** MediaTek's `0e8d`. That matters for
the Bluetooth kext's match table (see below).

## What the two projects are

| Project | Kext | What it does |
|---|---|---|
| [SimpleMtkWlan](https://github.com/flxxxxddd/SimpleMtkWlan) v1.5.0 | `AirportMtkWlan.kext` | real Wi-Fi interface via `IO80211Family`/Skywalk: native Wi-Fi menu, Keychain, private addresses. Built **per macOS IO80211 version** — Sequoia build vs Tahoe build, wrong one panics. |
| same | `SimpleMtkWlan.kext` | the card becomes an **Ethernet** interface (`enX`), joined through the [SimpleMTK](https://github.com/laobamac/SimpleMTKClient) menu-bar app. Version-agnostic. |
| [SimpleMtkBtFw](https://github.com/flxxxxddd/SimpleMtkBtFw) v1.1.0 | `SimpleMtkBtFw.kext` + `SimpleMtkBtPatcher.kext` | loads MediaTek BT firmware into the USB BT function, then macOS' own `bluetoothd` drives it; the patcher (Lilu plugin) fixes the BT-clock and ACL-flush bugs that otherwise leave AirPods silent. |

Only **one** of `AirportMtkWlan` / `SimpleMtkWlan` may be enabled — same PCI match.

## Why this matters for us: the IDs match (measured, in the release binaries)

- `AirportMtkWlan.kext/Contents/Info.plist` (1.5.0): `IOPCIPrimaryMatch` =
  `0x796114c3 0x060814c3 0x792214c3 0x061614c3` → **`14c3:7961` is the first entry.**
- `SimpleMtkWlan.kext/Contents/Info.plist` (1.5.0): `IOPCIPrimaryMatch` =
  `0x796114c3 0x060814c3 0x792214c3` → also matches.
- `SimpleMtkBtFw.kext/Contents/Info.plist` (1.1.0) has a personality
  `SimpleMtkBtFw_MT7921_13d3_3567`, `idVendor` 5075 (`0x13D3`), `idProduct` 13671 (`0x3567`)
  → **exactly our Bluetooth device**, plus a generic `0e8d` class match for other OEMs.

Upstream's own "tested hardware" table lists `14c3:7961` as *not tested* ("same chip family as
RZ608, expected to work"); the tested cards are MT7921K/RZ608 `14c3:0608` and MT7922. So: match
is proven, function is **assumed**.

## Prerequisites, checked against our current EFI

| Requirement | State |
|---|---|
| `Kernel > Quirks > DisableIoMapper` = `true` (driver has no AppleVTD DMA remap) | ✅ already `True` in `EFI/OC/config.plist` |
| Card must not be hidden (`vendor-id`/`device-id` forced to `0xFFFF`) | ✅ no `14c3`/`7961` keys anywhere in `config.plist`, no `SSDT-Disable_Network_*` in `EFI/OC/ACPI` |
| Lilu present | ✅ `Lilu 1.7.3` in `Kernel > Add` (AllInOne carries 1.7.2 — keep ours) |
| `BlueToolFixup.kext` (MinKernel `21.0.0`) for BT | ❌ not in the EFI yet |
| NVRAM `bluetoothInternalControllerInfo` = 14 zero bytes, `bluetoothExternalDongleFailed` = `00`, in **Add and Delete** (GUID `7C436110-…`) | ❌ not set yet; without them `bluetoothd` treats the card as an Apple/Broadcom module and crash-loops |
| No OCLP "Modern Wireless" root patch, no `IOSkywalkFamily` block/downgrade | ✅ nothing of the sort in this EFI |
| `AirportMtkWlan` build must match the OS | Sequoia 15.x → `AirportMtkWlan-Sequoia-*`, `MinKernel 24.2.0` / `MaxKernel 24.99.99` |

## Files fetched (2026-10-21, into `.downloads/mtk/`, git-ignored)

Verified with `sha256sum -c` against each release's published `SHA256SUMS.txt` — all OK:

| File | sha256 |
|---|---|
| `AirportMtkWlan-Sequoia-1.5.0-RELEASE.zip` (1,847,912 B) | `f5302337765cfadf6812be623b1441584b19fd8df90b896089ee750ad65c23d7` |
| `SimpleMtkWlan-1.5.0-RELEASE.zip` (1,839,685 B) | `9a67e9cee614d097c6b52b57932cfce45a9d2abf4668580de9c14d5b0a1d4967` |
| `SimpleMtkBtFw-1.1.0-RELEASE-AllInOne.zip` (1,538,778 B) | `3d053846bc8be8749238b2b5aed2d7edc891ae03a599ec0e7a358708c8846905` |
| `SHA256SUMS.Wlan.txt`, `SHA256SUMS.BtFw.txt` | published checksum lists |

The AllInOne zip contains `Kexts/{Lilu,BlueToolFixup,SimpleMtkBtFw,SimpleMtkBtPatcher}.kext` and a
`config-snippet.plist` with the exact `Kernel > Add` order and `NVRAM` entries.

## Known limits (from upstream, not measured here)

- No 802.11ax (HE) by default (`itlwm_he=1` is experimental), no WPA3-only (SAE) networks.
- No AWDL → no AirDrop / Handoff / Continuity.
- BT HFP microphone works but is quiet/choppy; wide-band speech (mSBC) unsupported.
- Warm reboots can leave the M.2 card wedged; the driver resets it, and a full power-off fixes it.
- `AirportMtkWlan` on **Sequoia** is "builds, not tested on hardware" upstream — the
  hardware-tested Sequoia path is `SimpleMtkWlan` + the SimpleMTK app.

## Plan (post-install, not needed for the installer)

Wi-Fi/BT are **not** needed to install: the install is offline from the stick and the wired
RTL8111 works via `RealtekRTL8111.kext`. Once macOS runs:

1. First try `SimpleMtkWlan.kext` + the SimpleMTK app (the hardware-tested Sequoia path).
   If the native menu is wanted, swap to `AirportMtkWlan.kext` with `MinKernel 24.2.0` /
   `MaxKernel 24.99.99` — one boot test each, never both enabled.
2. Bluetooth: add `BlueToolFixup` + `SimpleMtkBtFw` + `SimpleMtkBtPatcher` after Lilu, plus the
   two NVRAM variables (Add **and** Delete).
3. Copy the zips into the repo? No — `*.zip` is not ignored, so they stay in `.downloads/` and
   only their hashes are recorded here.
4. Every attempt: back up `EFI/`, one change at a time, record the boot log in `HANDOFF.md`.

## Applied 2026-10-22 (macOS is installed; first Wi-Fi attempt)

`AirportMtkWlan.kext` 1.5.0 (Sequoia build) is in `EFI/OC/Kexts/` and enabled in
`Kernel > Add` with `MinKernel 24.2.0` / `MaxKernel 24.99.99`, on both the repo config and the
offline stick's `EFI/OC/config.plist`. `SimpleMtkWlan.kext` is also copied but **disabled** — one
of the two only, ever. `ocvalidate`: No issues found. Backups:
`.downloads/recovery-backup/config.plist.before-wifi` (stick, before this change) and
`config.plist.before-rtl-off` (the step before).

Why the native-menu kext first: it needs **no userspace app**, and this machine has no network
until Wi-Fi works. The `SimpleMtkWlan` fallback needs the SimpleMTK menu-bar app, and
`laobamac/SimpleMTKClient` publishes **no prebuilt release** (checked the GitHub releases API:
empty), so that path would need Xcode on the Mac first — not available offline in a fresh install.

Also disabled at the same time (stick only): `RealtekRTL8111.kext`, because the boot that failed
after the install died in OpenCore right after its injection, with
`OCAK: Patching invalid size … for com.apple.iokit.IONetworkingFamily` /
`IOPCIFamily` and no `EXITBS:START`. Ethernet is not needed for an offline install; re-enable it
once the machine boots normally.

Rollback if the kext panics at boot: boot Linux (same laptop), then
`cp .downloads/recovery-backup/config.plist.before-wifi /run/media/<user>/OPENCORE/EFI/OC/config.plist`
or just set `Enabled=false` on the `AirportMtkWlan.kext` entry.
