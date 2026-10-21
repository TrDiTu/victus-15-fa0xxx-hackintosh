# Making the display work: Tiger Lake spoof

Apple has no driver for Alder Lake-P (`8086:46A6`), but it has one for Tiger Lake
(`9A49`, Gen12 Xe-LP, display engine 12). The installer only needs a *framebuffer*,
not acceleration, so present the iGPU as a Tiger Lake part and let Apple's TGL driver bind.

Base: 1401's stock build, which had `disable-gpu = True` on the iGPU (OpCore-Simplify
marked it unsupported and switched it off). That single key is why every earlier boot
stopped at `IOConsoleUsers: gIOScreenLockState 3`.

`DeviceProperties > Add > PciRoot(0x0)/Pci(0x2,0x0)`:

| Key | Value | Why |
|---|---|---|
| `device-id` | `499A0000` | 0x9A49 = TGL GT2, closest Xe-LP sibling |
| `AAPL,ig-platform-id` | `0000499A` | 0x00009A49 framebuffer/connector profile |
| `framebuffer-patch-enable` | `01000000` | let WhateverGreen patch connectors |
| `force-online` | `01000000` | don't wait for an EDID handshake |
| `complete-modeset` | `01000000` | program a full mode instead of adopting firmware's |
| `enable-max-pixel-clock-override` | `01000000` | allow the panel's pixel clock |
| `rps-control` | `01000000` | render power states |
| `hda-gfx` | `onboard-1` | HDMI/DP audio association |
| `built-in` / `AAPL,slot-name` | `00` / `built-in` | internal display |
| `model` | `Intel Iris Xe Graphics` | cosmetic |

Boot args during install: `-v debug=0x100 keepsyms=1 amfi=0x80 -vi2c-force-polling`.
Do **not** disable the iGPU; do **not** load the NVIDIA kexts (they cannot help the installer).

Reference: github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe (Raptor Lake-P `A7A0`,
same Xe-LP/display-engine-13 family). Their install config is this recipe; their
`NootedGreen` plugin is the post-install accelerator.
