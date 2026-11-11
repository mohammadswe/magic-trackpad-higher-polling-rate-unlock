<div align="center">

# ⚡️ Magic Trackpad Higher Polling Rate Unlock

**Double your Apple Magic Trackpad report rate from 60Hz to ~90–125Hz on any 60Hz macOS display.**  
*Zero lag. Half the cursor latency. 100% open-source.*

[![macOS](https://img.shields.io/badge/macOS-13%20%7C%2014%20%7C%2015-blue?logo=apple\&logoColor=white)](#system-requirements)
[![Apple Silicon & Intel](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-success)](#system-requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)
[![Zero Proprietary Binaries](https://img.shields.io/badge/Dependencies-Zero%20Proprietary%20Binaries-orange)](#dependencies)

[Quick Start](#-quick-start) • [The Technical Bottleneck](#-the-hidden-bottleneck-8000µs-vs-60hz-vsync) • [How It Works](#-the-solution-120hz-compositor-promotion) • [CLI Automation](#-cli-usage--headless-automation) • [FAQ](#-frequently-asked-questions)

</div>

---

## 🔍 The Hidden Bottleneck: 8000µs vs 60Hz VSYNC

Every Apple Magic Trackpad (Magic Trackpad 2 & 3, both Lightning and USB-C) hardware controller transmits coordinate and gesture packets at an internal report interval of **`ReportInterval = 8000 µs` (8.0 milliseconds)**. That corresponds to a hardware polling capability of **125Hz** (dynamically fluctuating between **90Hz and 125Hz** over Bluetooth, and a rock-solid **125Hz** over USB).

You can verify this directly on any Mac in your terminal:
```bash
ioreg -r -c IOHIDInterface | grep -B 2 -A 8 -i "reportinterval"
```
```text
"Product" = "Magic Trackpad"
"ProductID" = 804
"ReportInterval" = 8000
```

### 🛑 Why Does It Feel Sluggish on 60Hz Monitors?
When macOS is connected to a standard **60Hz monitor** (such as the Apple Studio Display, LG UltraFine 4K/5K, Dell/ASUS external displays, or non-ProMotion MacBooks), macOS's compositor (`WindowServer`) anchors its internal event loop tick directly to the primary display's VSYNC clock: **16.66ms per frame**.

Even though the trackpad hardware dispatches touch packets every **8.0ms**, macOS can only process and dispatch pointer events every **16.66ms**:

```
Hardware Polling (Trackpad): [ 8ms ][ 8ms ][ 8ms ][ 8ms ][ 8ms ][ 8ms ] (125Hz)
                                |      |      |      |      |      |
macOS WindowServer (60Hz):     [     16.66ms     ][     16.66ms     ] (60Hz)
Dispatched Pointer Events:     ( Event 1 )        ( Event 2 )       <-- 50% packets coalesced/lost
```

* **50% of incoming touch packets are discarded or merged.**
* Browsers (`pointermove`, `mousemove`) cap cursor event rates at **60 events/sec**.
* Input latency is locked at **~16.7ms**, producing visible micro-stutter and drag latency.

---

## 💡 The Solution: 120Hz Compositor Promotion

This utility provisions a high-performance 120Hz virtual screen inside macOS and hardware-mirrors that virtual screen onto your physical 60Hz monitor.

When any display in the macOS desktop topology requests a 120Hz refresh cadence:
1. **`WindowServer` immediately promotes its compositor clock from 60Hz to 120Hz (8.33ms per tick).**
2. macOS and web browsers double their input event loop frequency to 120Hz.
3. Every single 8ms hardware coordinate report from your Magic Trackpad now finds an active frame tick.
4. **Touch reporting instantly unlocks to real-time 90–125Hz**, cutting tracking latency in half (**~16.7ms $\rightarrow$ ~8.3ms**).
5. The physical monitor continues refreshing pixels smoothly at its native 60Hz hardware cadence without tearing or frame jitter.

```
Hardware Polling (Trackpad): [ 8ms ][ 8ms ][ 8ms ][ 8ms ][ 8ms ][ 8ms ] (125Hz)
                                |      |      |      |      |      |
Virtual Dummy (120Hz):         [  8.33ms  ][  8.33ms  ][  8.33ms  ] (120Hz Compositor Link)
Dispatched Pointer Events:     ( Event 1  )( Event 2  )( Event 3  ) <-- 100% packets processed live!
Physical Display (60Hz):       [        16.66ms        ][  ...     ] (Presents alternate frames)
```

---

## 🚀 Quick Start

### 1. Download or Clone
```bash
git clone https://github.com/your-username/magic-trackpad-higher-polling-rate-unlock.git
cd magic-trackpad-higher-polling-rate-unlock
```

### 2. Compile App Bundles
```bash
make
```
This builds two portable, self-contained apps inside the `apps/` directory:
* **`apps/Unlock Magic Trackpad Polling.app`** — Activates 120Hz mirror, chimes with native sound (`Glass`), and launches the TestUFO mouse rate benchmark.
* **`apps/Restore Native 60Hz Display.app`** — Disconnects the dummy, chimes with standard sound (`default`), and returns display directly to native 60Hz.

### 3. Double-Click to Activate!
Drag either app to `/Applications`, your Dock, or Spotlight.

> [!TIP]
> **Prerequisite:** This tool utilizes [BetterDisplay](https://betterdisplay.pro) for virtual display driver bridging. If BetterDisplay is not installed, the app will offer to install it automatically via `brew install --cask betterdisplay` or guide you to download it directly. Zero proprietary binaries are shipped in this repository.

---

## 🔬 Live Verification: Before & After

Once activated, your default browser opens [`https://testufo.com/mouserate`](https://testufo.com/mouserate):

| Metric | Native 60Hz Display | With 120Hz Compositor Promotion |
| :--- | :---: | :---: |
| **Compositor Clock** | 60Hz (16.66 ms) | **120Hz (8.33 ms)** |
| **Browser `mousemove` Rate** | ~60 Hz | **~90–125 Hz** |
| **Wired USB Report Rate** | 60 Hz (Throttled) | **125 Hz (Maximized)** |
| **Touch-to-Screen Latency** | ~16.7 ms | **~8.3 ms (50% reduction)** |
| **Visual Micro-Stutter** | Noticeable cursor drag | **Liquid-smooth tracking** |

---

## 💻 CLI Usage & Headless Automation

The engine includes a complete headless POSIX/Bash automation CLI for terminal users, Raycast scripts, launchd daemons, or SSH workflows:

```bash
bin/trackpad-unlock.sh [COMMAND] [OPTIONS]
```

### Subcommands
| Command | Description |
| :--- | :--- |
| `enable` | Profiles display, provisions 120Hz dummy, activates mirror, notifies, and opens TestUFO. |
| `disable` | Disconnects virtual dummy and cleanly restores native 60Hz display. |
| `status` | Reports detailed physical display, dummy mirror, and trackpad hardware status. |
| `test` | Runs diagnostic audit on trackpad HID packet report intervals. |
| `install-deps` | Runs automated Homebrew cask installation for BetterDisplay. |
| `cleanup` | Fully deletes virtual dummies and cleans up stored preferences. |

### CLI Options
* `--json` — Output machine-readable JSON status messages to stdout.
* `--headless` — Suppress all GUI dialogs, banners, and browser tabs (ideal for automation).
* `--no-browser` — Activate 120Hz mirror without opening TestUFO.
* `--force` — Bypass the ProMotion/high-refresh guardrail.
* `--target <NAME>` — Target a specific physical monitor by name in multi-monitor setups.
* `-v, --verbose` — Enable detailed debug logs to stderr.

### Example: Inspect Status via JSON
```bash
bin/trackpad-unlock.sh status --json
```
```json
{
  "status": "ok",
  "betterdisplay_installed": true,
  "dummy_created": true,
  "dummy_connected": true,
  "dummy_mirrored": true,
  "physical_display": {
    "display_name": "Studio Display",
    "refresh_rate": 60,
    "native_width": 5120,
    "native_height": 2880,
    "aspect_ratio_str": "16:9"
  },
  "trackpad": {
    "detected": true,
    "product": "Magic Trackpad",
    "transport": "USB",
    "report_interval_us": 8000,
    "hardware_polling_hz": 125
  }
}
```

---

## 🛡️ Built-in ProMotion Guardrails

If you run this utility on a display that is **already running at $\ge 100\text{Hz}$** (such as a MacBook Pro with Liquid Retina XDR ProMotion, or a 144Hz/240Hz external gaming monitor):
* The engine detects that cursor polling is already maximized.
* It safely exits (exit code `2`) with a gentle notification chime (`Blow`).
* No unnecessary virtual dummies are created, preserving GPU memory and native variable refresh timing.

---

## 🖥️ Multi-Monitor Topologies

The detection engine (`bin/detect-display.py`) intelligently handles multi-display setups:
* **MacBook Pro (120Hz) + External 60Hz Monitor (e.g. Studio Display):** Detects that the external screen is 60Hz and applies the 120Hz mirror specifically to the external display.
* **Dual 60Hz Monitors:** Automatically targets the primary display (`spdisplays_main`) or allows targeting via `--target "Display Name"`.
* **UltraWide & Non-16:9 Panels:** Dynamically calculates aspect ratio via GCD reduction ($16:9$, $16:10$, $3:2$, $21:9$, $32:9$) and provisions matching dummy geometry.

---

## ❓ Frequently Asked Questions

#### Does this drain battery life?
The virtual dummy consumes a minimal GPU framebuffer allocation (~15–25MB of unified memory). The Metal compositor rendering cost is virtually negligible on Apple Silicon.

#### Does BetterDisplay require a paid license for this?
**No.** Creating virtual screens and establishing basic hardware mirrors are fully functional in the free version of BetterDisplay.

#### Does this work with Magic Mouse?
**Yes!** The Magic Mouse also shares the 8000µs (125Hz) Bluetooth packet interval. Enabling 120Hz compositor promotion unlocks the exact same 90–125Hz pointer smoothness.

#### How do I completely uninstall?
Run:
```bash
bin/trackpad-unlock.sh cleanup
make clean
```
This removes the virtual dummy, resets BetterDisplay preferences, and deletes compiled app bundles.

---

## 📄 License

Released under the [MIT License](LICENSE). Copyright © 2026.
