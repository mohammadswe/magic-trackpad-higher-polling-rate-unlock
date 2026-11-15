# Unlock Higher Polling Rate On Your Magic Trackpad

Double your Apple Magic Trackpad report rate from **60Hz to ~120Hz** on any 60Hz Mac display.

Enjoy visibly smoother cursor tracking, half the input lag, and a more responsive desktop—with one click.

---

## How It Works

* **Your Trackpad is already fast:** The Magic Trackpad hardware actually tracks your fingers at **125Hz** (sending touch updates every 8ms).
* **The macOS Bottleneck:** When connected to a 60Hz monitor (like an Apple Studio Display, an external 4K/1440p monitor, or a MacBook Air), macOS slows down cursor updates to match the screen's 60Hz rate. Half of your touch packets get discarded.
* **The Fix:** This tool creates an invisible 120Hz virtual screen and mirrors it to your monitor. This tells macOS to run its cursor and gesture engine at 120Hz, letting your trackpad run at its full hardware speed (~90–125Hz) while your monitor continues displaying cleanly at 60Hz.

---

## 🚀 How to Use

[Check your current polling rate at](https://testufo.com/mouserate)

### 1. One-Click Apps
Inside the `apps/` folder, you'll find two ready-to-use apps:
* **`Unlock Magic Trackpad Polling.app`** — Turns on the 120Hz unlock. You'll hear a chime, get a notification, and [TestUFO](https://testufo.com/mouserate) will open in your browser so you can test it live.
* **`Restore Native 60Hz Display.app`** — Turns off the virtual screen and returns your display back to pure native 60Hz.

*(Tip: You can drag these apps to your `/Applications` folder, your Dock, or launch them with Spotlight or Raycast!)*

### 2. Verify Your New Polling Rate
When you activate the app, it automatically opens [testufo.com/mouserate](https://testufo.com/mouserate):
* **Before:** Capped at **~60 Hz**.
* **After:** Smoothly reads **~90–125 Hz** over Bluetooth (or a locked **125 Hz** when plugged in via cable).

---

## 💻 Terminal / CLI Usage (Optional)

If you prefer using the command line:

```bash
# Turn on 120Hz unlock
./bin/trackpad-unlock.sh enable

# Turn off and restore native 60Hz
./bin/trackpad-unlock.sh disable

# Check current status of display, mirror, and trackpad
./bin/trackpad-unlock.sh status
```

---

## 📋 Requirements & Notes

* **macOS 13+** on Apple Silicon (M1/M2/M3/M4) or Intel.
* **[BetterDisplay](https://betterdisplay.pro)**: Used behind the scenes to create the virtual screen. If you don't have it installed, the app will ask if you'd like to install it automatically via Homebrew (`brew install --cask betterdisplay`) or download it free from their website.
* **Already on a 120Hz ProMotion display?** If your primary screen is already 120Hz (such as a 14" or 16" MacBook Pro screen or a 144Hz gaming monitor), the tool will detect it and let you know your trackpad is already running at full speed.
* **Magic Mouse:** Also works with the Apple Magic Mouse!

---

## 📄 License

MIT License. Free and open source.
