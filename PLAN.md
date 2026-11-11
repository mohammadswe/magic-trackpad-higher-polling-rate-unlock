# Engineering Plan: Magic Trackpad Higher Polling Rate Unlock

## 1. Executive Summary & Objective

This project packages the 120Hz virtual dummy mirroring technique discovered in `display-tweaks` into a standalone, one-click public utility: **`Unlock Magic Trackpad Polling.app`**.

### The Problem
* The Apple Magic Trackpad 2 & 3 hardware is capable of transmitting touch reports at **125Hz** over Bluetooth (`ReportInterval = 8000 µs`), typically fluctuating between **90Hz and 125Hz** during active movement.
* On macOS systems connected to **60Hz displays** (including Apple Studio Display, external 4K/1440p monitors, and non-ProMotion MacBooks/Mac minis), macOS's `WindowServer` compositor and web browser engines (Safari, Chrome, Arc) align pointer event dispatching to the 60Hz display VSYNC.
* This artificially throttles trackpad cursor updates to 60Hz, introducing noticeable cursor latency and jitter.

### The Solution
* By creating a virtual dummy display configured to run at **120Hz** and hardware-mirroring it to the user's physical display, macOS's `WindowServer` display link is promoted to **120Hz**.
* This unthrottles the OS and browser event loop, immediately unlocking the Magic Trackpad's full **90–125Hz hardware polling rate**.
* While the physical 60Hz panel continues to refresh pixels at 60Hz, cursor tracking and gesture calculation pipeline latency drops from ~16.6ms to ~8ms, creating an instantly noticeable improvement in trackpad fluidity.

---

## 2. Architecture & System Flow

```
                                      +-------------------------------+
                                      |     Apple Magic Trackpad      |
                                      |   (Hardware: 125Hz / 8ms)     |
                                      +---------------+---------------+
                                                      |
                                                      | Bluetooth HID Packets (~90-125Hz)
                                                      v
+-------------------------------+     +---------------+---------------+
|       Physical Display        |     |       macOS WindowServer      |
|     (e.g., 4K / 5K 60Hz)      |     | (Clocked to 120Hz by Dummy)   |
+---------------+---------------+     +---------------+---------------+
                ^                                     |
                | Hardware Mirror                     | Unthrottled Event Dispatch
                | (Drops alternate frames)            v
+---------------+---------------+     +---------------+---------------+
|  BetterDisplay 120Hz Dummy    |<----+  Browser / Apps / Pointer     |
| (Matches Native Res & Aspect) |     | (Dispatches @ 90-125Hz)       |
+-------------------------------+     +-------------------------------+
```

---

## 3. Core Requirements & Boundaries

1. **One-Click Native macOS UX (`Option C`)**:
   - The end user must be able to double-click a single `.app` bundle from Finder, Spotlight, or Raycast.
   - No required terminal interaction for basic usage.
   - Includes a companion "Restore Native" toggle/app to revert back instantly.
2. **Zero Proprietary Binary Shipping**:
   - **Do NOT bundle `BetterDisplay.app`** or binary files in this git repository (license violation / repo bloat).
   - The tool must detect whether BetterDisplay is installed. If missing, it must offer automated installation via Homebrew (`brew install --cask betterdisplay`) or open the official download page.
3. **Automatic Display Profiling**:
   - Do **NOT** hardcode resolutions (such as Studio Display 5K).
   - Detect the user's primary connected display: resolution, aspect ratio, and active refresh rate.
4. **60Hz Guardrail**:
   - If the user's primary display is **already running at ≥ 120Hz** (e.g. built-in ProMotion MacBook Pro screen, 144Hz gaming monitor):
     - Abort gracefully with an informative dialog: *"Your display is already running at [X]Hz! Magic Trackpad higher polling rate is already unlocked on this screen."*
     - Do not create unnecessary dummy monitors.
5. **Instant Live Proof**:
   - Upon successful mirroring, display a native macOS notification and immediately launch `https://testufo.com/mouserate` in the user's default browser so they can see the ~90–125Hz polling rate in real time.
6. **Graceful Error Handling**:
   - If any step fails (permissions, display detection, dummy creation), display a human-readable macOS dialog explaining what went wrong and how to fix it.

---

## 4. Proposed Repository Structure

```
magic-trackpad-higher-polling-rate-unlock/
├── README.md                          # Public viral-ready GitHub documentation
├── LICENSE                            # MIT License
├── Makefile                           # Optional build automation for compiling .app bundles
├── bin/
│   ├── trackpad-unlock.sh             # Core headless POSIX/Bash engine script
│   └── detect-display.py              # Robust display & refresh rate detection helper
├── apps/
│   ├── Unlock Magic Trackpad Polling.app/  # Clickable launcher bundle (AppleScript/Automator)
│   └── Restore Native 60Hz Display.app/    # Clickable revert bundle
└── assets/
    ├── applet.icns                    # Custom modern macOS app icon
    └── demo.gif                       # Visual demonstration for README / Reddit
```

---

## 5. Detailed Component Specifications

### Component A: Display & System Detection Engine (`bin/detect-display.py`)

A pure Python script (uses macOS built-in `/usr/bin/python3`, zero pip dependencies) parsing `system_profiler SPDisplaysDataType -json`:

```python
# Key logic to extract:
# 1. Identify active primary (main) physical display:
#    - Filter out existing virtual screens (vendor ID 896 / BDV or display_type 'virtual').
#    - Identify 'spdisplays_main' == 'spdisplays_yes' (or primary external).
# 2. Extract:
#    - Display Name (e.g. "Studio Display", "DELL U2720Q")
#    - Current Refresh Rate (Hz integer, e.g. 60, 120, 144)
#    - Pixel Resolution (Width x Height, e.g. 3840x2160, 5120x2880, 2560x1440)
#    - Aspect Ratio (simplified ratio, e.g. 16:9, 16:10, 21:9)
# 3. Output JSON format to stdout:
#    {
#      "status": "ok",
#      "display_name": "LG UltraFine",
#      "refresh_rate": 60,
#      "is_60hz": true,
#      "native_width": 3840,
#      "native_height": 2160,
#      "aspect_w": 16,
#      "aspect_h": 9
#    }
```

### Component B: Core Unlocking Engine (`bin/trackpad-unlock.sh`)

Supports subcommands: `enable`, `disable`, `status`, `test`.

#### 1. Prerequisite Verification (`check_deps`)
* Check for BetterDisplay at `/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay`.
* If not found:
  * Check if `brew` exists in `$PATH` (`/opt/homebrew/bin/brew` or `/usr/local/bin/brew`).
  * If `brew` is available: prompt user via GUI dialog (`osascript`): *"BetterDisplay is required to create the 120Hz virtual mirror. Would you like to install it automatically via Homebrew?"*
  * If user accepts: execute `brew install --cask betterdisplay` with progress reporting.
  * If Homebrew is absent or user declines: open `https://github.com/waydabber/BetterDisplay/releases` and show manual install instructions.

#### 2. Display Refresh Rate Check (`validate_display`)
* Run `detect-display.py`.
* If `refresh_rate >= 100`:
  * Exit with code 0 and show dialog:
    *"Your display '[Name]' is already running at [Rate]Hz. Your Magic Trackpad is already operating at its maximum polling rate!"*

#### 3. Virtual Screen Creation (`create_dummy`)
* Use BetterDisplay CLI:
  ```bash
  BETTERDISPLAY="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
  ```
* Check if a dummy named `Trackpad 120Hz Dummy` already exists:
  ```bash
  $BETTERDISPLAY get -identifiers
  ```
* If not present, create it with matching aspect ratio:
  ```bash
  $BETTERDISPLAY create -type=VirtualScreen \
    -virtualScreenName="Trackpad 120Hz Dummy" \
    -aspectWidth=$ASPECT_W \
    -aspectHeight=$ASPECT_H
  ```
* Configure custom 120Hz refresh rates in defaults:
  ```bash
  defaults write pro.betterdisplay.BetterDisplay "refreshRates@VirtualScreen:<TAG>" -string "[60, 120]"
  defaults write pro.betterdisplay.BetterDisplay "useCustomRefreshRates@VirtualScreen:<TAG>" -bool true
  ```

#### 4. Mirroring Activation (`activate_mirror`)
* Connect dummy:
  ```bash
  $BETTERDISPLAY set -name="Trackpad 120Hz Dummy" -connected=on
  sleep 0.5
  ```
* Query dummy mode list to select the matching native resolution at 120Hz:
  ```bash
  $BETTERDISPLAY get -name="Trackpad 120Hz Dummy" -displayModeList
  ```
* Find mode matching `${NATIVE_WIDTH}x${NATIVE_HEIGHT} HiDPI 120Hz` (or closest HiDPI native mode).
* Set mode and mirror to target physical display:
  ```bash
  $BETTERDISPLAY set -name="Trackpad 120Hz Dummy" -displayModeNumber=$MODE_NUM
  $BETTERDISPLAY set -name="Trackpad 120Hz Dummy" -mirror=on -targetName="$TARGET_DISPLAY_NAME"
  ```

#### 5. Post-Activation Verification & Test UFO (`verify_and_open`)
* Trigger macOS notification:
  ```bash
  osascript -e 'display notification "Active: 120Hz Mirror enabled on '$TARGET_DISPLAY_NAME'. Trackpad polling unlocked!" with title "Magic Trackpad Polling Unlock"'
  ```
* Open TestUFO in default browser:
  ```bash
  open "https://testufo.com/mouserate"
  ```

#### 6. Deactivation Routine (`disable`)
* Disconnect dummy and unmirror:
  ```bash
  $BETTERDISPLAY set -name="Trackpad 120Hz Dummy" -connected=off >/dev/null 2>&1 || true
  osascript -e 'display notification "120Hz dummy disconnected. Reverted to native display." with title "Magic Trackpad Polling Unlock"'
  ```

---

### Component C: One-Click Clickable Apps (`apps/`)

Compile two lightweight AppleScript applets via `osacompile`:

1. **`Unlock Magic Trackpad Polling.app`**:
   - Executes `bin/trackpad-unlock.sh enable`.
   - Handles user-facing alert dialogs for any errors.
   - Packaged with an icon reflecting 120Hz speed / trackpad.
2. **`Restore Native 60Hz Display.app`**:
   - Executes `bin/trackpad-unlock.sh disable`.
   - One-click restore for peace of mind.

---

## 6. Edge Cases & Safety Mechanisms

| Scenario / Edge Case | Expected Handling |
| :--- | :--- |
| **User has multiple 60Hz displays** | Detect the display with mouse cursor (`displayWithMouse`) or primary display, or display a clean selection dialog if ambiguous. |
| **User is on a ProMotion MacBook (120Hz built-in)** | Guardrail detects 120Hz immediately, alerts user that unlock is unneeded, exits cleanly without creating dummy. |
| **BetterDisplay permissions missing** | Detect if BetterDisplay cannot capture screens or mirror; open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` and guide user. |
| **Display sleep / disconnect** | BetterDisplay persists virtual dummy settings across sleep; `trackpad-unlock.sh enable` is idempotent. |
| **Trackpad connected via USB cable** | Polling rate is a locked 125Hz; still benefits from 120Hz compositor event dispatching. |

---

## 7. Public Viral Launch Plan (Reddit / GitHub)

### Target Communities
* `r/mac`, `r/apple`, `r/macsetups`, `r/MacOS`, Hacker News (`Show HN`).

### The Post Outline
1. **The Hook**: "TIL your Magic Trackpad actually hardware-polls at 125Hz, but macOS caps it to 60Hz if you're on a 60Hz display. Here's a 1-click open-source tool to unlock it."
2. **The Verification (`ioreg`)**: Show terminal output proving `ReportInterval = 8000 µs` (125Hz).
3. **The Proof**: Side-by-side video/GIF showing `testufo.com/mouserate` jumping from 60Hz to ~110–125Hz.
4. **The Link**: Direct GitHub repo with clean instructions and the one-click `.app`.

---

## 8. Step-by-Step Implementation Roadmap for Future Agent

- [ ] **Phase 1: Detection Engine**
  - Implement and test `bin/detect-display.py` with mock outputs for 60Hz, 120Hz, single display, and dual display.
- [ ] **Phase 2: Core Shell Engine**
  - Implement `bin/trackpad-unlock.sh` with `enable`, `disable`, and `status` routines.
  - Implement Homebrew auto-install helper and BetterDisplay CLI bridge.
- [ ] **Phase 3: AppleScript Applet Bundles**
  - Generate and sign `Unlock Magic Trackpad Polling.app` and `Restore Native 60Hz Display.app` using `osacompile`.
  - Add icons to `Contents/Resources/applet.icns`.
- [ ] **Phase 4: Verification & Test UFO Bridge**
  - Verify seamless browser popup to `https://testufo.com/mouserate` on completion.
- [ ] **Phase 5: Public Documentation**
  - Write high-converting, tech-nerd-friendly `README.md` with benchmark instructions and clear diagrams.
