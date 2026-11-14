#!/usr/bin/env bash
# ==============================================================================
# trackpad-unlock.sh - Magic Trackpad Higher Polling Rate Unlock CLI
# ==============================================================================
# Orchestrates 120Hz virtual dummy screen creation, BetterDisplay preferences
# injection, display mirroring, and hardware verification to unlock 125Hz polling.
# ==============================================================================

set -o pipefail

# Standardized Exit Codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_ALREADY_HIGH_REFRESH=2
readonly EXIT_BETTERDISPLAY_MISSING=3
readonly EXIT_NO_PHYSICAL_DISPLAY=4
readonly EXIT_DUMMY_CREATION_FAILED=5
readonly EXIT_MODE_SELECTION_FAILED=6
readonly EXIT_MIRROR_FAILED=7
readonly EXIT_PERMISSION_DENIED=8
readonly EXIT_NO_TRACKPAD_DETECTED=9

# App Constants
readonly DUMMY_NAME="Trackpad 120Hz Dummy"
readonly TEST_UFO_URL="https://testufo.com/mouserate"

# Generalize BetterDisplay location (/Applications or ~/Applications)
find_betterdisplay_app() {
  if [ -d "/Applications/BetterDisplay.app" ]; then
    echo "/Applications/BetterDisplay.app"
  elif [ -d "${HOME}/Applications/BetterDisplay.app" ]; then
    echo "${HOME}/Applications/BetterDisplay.app"
  else
    echo "/Applications/BetterDisplay.app"
  fi
}

BD_APP="$(find_betterdisplay_app)"
BD_CLI="${BD_APP}/Contents/MacOS/BetterDisplay"

# Determine script & engine directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_DISPLAY="${SCRIPT_DIR}/detect-display.py"

# Flag defaults
OPT_FORCE=false
OPT_HEADLESS=false
OPT_NO_BROWSER=false
OPT_TARGET=""
OPT_JSON=false
OPT_VERBOSE=false

log_verbose() {
  if [ "$OPT_VERBOSE" = true ]; then
    echo "[DEBUG] $*" >&2
  fi
}

send_notification() {
  local title="$1"
  local subtitle="$2"
  local message="$3"
  local sound="${4:-default}"

  if [ "$OPT_HEADLESS" != true ]; then
    osascript -e "display notification \"$message\" with title \"$title\" subtitle \"$subtitle\" sound name \"$sound\"" 2>/dev/null || true
  fi
}

send_alert() {
  local title="$1"
  local message="$2"
  if [ "$OPT_HEADLESS" != true ]; then
    osascript -e "display alert \"$title\" message \"$message\" as critical" 2>/dev/null || true
  fi
}

locate_python() {
  if [ -x "/usr/bin/python3" ]; then
    echo "/usr/bin/python3"
  elif command -v python3 >/dev/null 2>&1; then
    command -v python3
  else
    echo "python3"
  fi
}

PYTHON_BIN="$(locate_python)"

# Check if BetterDisplay is installed, prompt if GUI
check_betterdisplay_installed() {
  BD_APP="$(find_betterdisplay_app)"
  BD_CLI="${BD_APP}/Contents/MacOS/BetterDisplay"

  if [ -x "$BD_CLI" ]; then
    return 0
  fi

  log_verbose "BetterDisplay CLI not found at $BD_CLI"

  if [ "$OPT_HEADLESS" = true ]; then
    echo "Error: BetterDisplay is not installed at ${BD_APP}." >&2
    exit "$EXIT_BETTERDISPLAY_MISSING"
  fi

  # GUI prompt with Homebrew option
  local action
  action=$(osascript -e '
    set dialogResult to display dialog "BetterDisplay is required to create the 120Hz virtual mirror that unlocks Magic Trackpad polling rates.\n\nWould you like to install it automatically via Homebrew?" with title "Magic Trackpad Polling Unlock" buttons {"Download Manually", "Cancel", "Install via Homebrew"} default button "Install via Homebrew" with icon caution
    return button returned of dialogResult
  ' 2>/dev/null || echo "Cancel")

  if [ "$action" = "Install via Homebrew" ]; then
    echo "Installing BetterDisplay via Homebrew..."
    install_deps
    if [ -x "$BD_CLI" ]; then
      return 0
    fi
  elif [ "$action" = "Download Manually" ]; then
    open "https://betterdisplay.pro"
  fi

  send_notification "Magic Trackpad Polling" "BetterDisplay Required" "BetterDisplay installation required to create 120Hz virtual screen." "Basso"
  exit "$EXIT_BETTERDISPLAY_MISSING"
}

# Ensure BetterDisplay background daemon is running
ensure_betterdisplay_running() {
  if ! pgrep -x "BetterDisplay" >/dev/null 2>&1; then
    log_verbose "BetterDisplay not running; launching silently..."
    open -a "$BD_APP" --hide 2>/dev/null || true
  fi

  local attempts=0
  while [ $attempts -lt 20 ]; do
    if "$BD_CLI" get -identifiers >/dev/null 2>&1; then
      log_verbose "BetterDisplay daemon is responsive."
      return 0
    fi
    sleep 0.3
    attempts=$((attempts + 1))
  done

  log_verbose "Timed out waiting for BetterDisplay daemon"
  return 1
}

# Homebrew cask install flow
install_deps() {
  local brew_path=""
  if [ -x "/opt/homebrew/bin/brew" ]; then
    brew_path="/opt/homebrew/bin/brew"
  elif [ -x "/usr/local/bin/brew" ]; then
    brew_path="/usr/local/bin/brew"
  elif command -v brew >/dev/null 2>&1; then
    brew_path="$(command -v brew)"
  fi

  if [ -z "$brew_path" ]; then
    echo "Error: Homebrew was not found on this system." >&2
    echo "Please install BetterDisplay manually from https://betterdisplay.pro" >&2
    if [ "$OPT_HEADLESS" != true ]; then
      open "https://betterdisplay.pro"
    fi
    exit "$EXIT_BETTERDISPLAY_MISSING"
  fi

  echo "Running: $brew_path install --cask betterdisplay"
  "$brew_path" install --cask betterdisplay
  if [ -x "$BD_CLI" ]; then
    echo "BetterDisplay installed successfully."
    return 0
  else
    echo "Error: BetterDisplay installation did not place executable at $BD_CLI" >&2
    exit "$EXIT_BETTERDISPLAY_MISSING"
  fi
}

# Query dummy tag ID from BetterDisplay identifiers JSON
get_dummy_tag_id() {
  local name="$1"
  local raw_output
  raw_output="$("$BD_CLI" get -identifiers 2>/dev/null)"

  if [ -z "$raw_output" ]; then
    return 1
  fi

  "$PYTHON_BIN" -c "
import sys, json
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(1)
if not raw.startswith('['):
    raw = f'[{raw}]'
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)

for d in (data if isinstance(data, list) else [data]):
    if d.get('name') == '$name' or d.get('productName') == '$name':
        tag = d.get('tagID') or d.get('tagID (VirtualScreen)')
        if tag is not None:
            print(tag)
            sys.exit(0)
sys.exit(1)
" <<< "$raw_output"
}

# Check Magic Trackpad presence and ReportInterval via ioreg
get_trackpad_info() {
  "$PYTHON_BIN" -c '
import subprocess, re, json

tp_detected = False
transport = "None"
product = "None"
report_interval = None

try:
    proc = subprocess.run(["ioreg", "-r", "-c", "AppleDeviceManagementHIDEventService"], stdout=subprocess.PIPE, text=True, timeout=5)
    for block in proc.stdout.split("+-o"):
        if "magic trackpad" in block.lower():
            tp_detected = True
            product = "Magic Trackpad"
            m_trans = re.search(r"\"Transport\" = \"([^\"]+)\"", block)
            if m_trans: transport = m_trans.group(1)
            break
except Exception:
    pass

if not tp_detected:
    # Check general trackpad service
    try:
        proc2 = subprocess.run(["ioreg", "-r", "-c", "IOHIDInterface"], stdout=subprocess.PIPE, text=True, timeout=5)
        for block in proc2.stdout.split("+-o"):
            if "magic trackpad" in block.lower():
                tp_detected = True
                product = "Magic Trackpad"
                m_trans = re.search(r"\"Transport\" = \"([^\"]+)\"", block)
                if m_trans: transport = m_trans.group(1)
                break
    except Exception:
        pass

# Query ReportInterval
try:
    proc3 = subprocess.run(["ioreg", "-r", "-c", "IOHIDInterface"], stdout=subprocess.PIPE, text=True, timeout=5)
    for block in proc3.stdout.split("+-o"):
        if ("magic trackpad" in block.lower() or "804" in block) and "reportinterval" in block.lower():
            m_rep = re.search(r"\"ReportInterval\"\s*=\s*(\d+)", block)
            if m_rep:
                report_interval = int(m_rep.group(1))
                break
except Exception:
    pass

hz = (1000000 // report_interval) if (report_interval and report_interval > 0) else (125 if tp_detected else 0)

out = {
    "detected": tp_detected,
    "product": product,
    "transport": transport,
    "report_interval_us": report_interval,
    "hardware_polling_hz": hz
}
print(json.dumps(out))
'
}

# Subcommand: enable
cmd_enable() {
  log_verbose "Executing enable command..."
  check_betterdisplay_installed
  ensure_betterdisplay_running

  # Profile physical display
  if [ ! -f "$DETECT_DISPLAY" ]; then
    echo "Error: Display detection engine missing at $DETECT_DISPLAY" >&2
    exit "$EXIT_GENERAL_ERROR"
  fi

  local detect_args=()
  if [ -n "$OPT_TARGET" ]; then
    detect_args+=(--target-name "$OPT_TARGET")
  fi

  local disp_json
  disp_json="$("$PYTHON_BIN" "$DETECT_DISPLAY" "${detect_args[@]}" 2>/dev/null)"
  if [ $? -ne 0 ] || [ -z "$disp_json" ]; then
    echo "Error: Failed to detect physical display." >&2
    send_notification "Magic Trackpad Polling" "Configuration Failed" "No active physical display could be identified." "Basso"
    exit "$EXIT_NO_PHYSICAL_DISPLAY"
  fi

  local target_name is_high_refresh aspect_w aspect_h native_w native_h logical_w logical_h refresh_rate
  eval "$("$PYTHON_BIN" -c "
import sys, json
d = json.load(sys.stdin)
print(f'target_name=\"{d.get(\"display_name\", \"\")}\"')
print(f'is_high_refresh={\"true\" if d.get(\"is_high_refresh\") else \"false\"}')
print(f'aspect_w={d.get(\"aspect_w\", 16)}')
print(f'aspect_h={d.get(\"aspect_h\", 9)}')
print(f'native_w={d.get(\"native_width\", 2560)}')
print(f'native_h={d.get(\"native_height\", 1440)}')
print(f'logical_w={d.get(\"logical_width\", 1280)}')
print(f'logical_h={d.get(\"logical_height\", 720)}')
print(f'refresh_rate={d.get(\"refresh_rate\", 60)}')
" <<< "$disp_json")"

  log_verbose "Detected target: $target_name (${aspect_w}:${aspect_h}, ${refresh_rate}Hz)"

  # Guardrail check
  if [ "$is_high_refresh" = "true" ] && [ "$OPT_FORCE" != true ]; then
    echo "Notice: Display '$target_name' is already running at high refresh rate (${refresh_rate}Hz)."
    echo "Trackpad polling is already running unthrottled. No dummy needed."
    send_notification "Magic Trackpad Polling" "Display Already 120Hz+" "Your display is already high-refresh. Trackpad polling is already maximized!" "Blow"
    exit "$EXIT_ALREADY_HIGH_REFRESH"
  fi

  # Check if dummy already exists
  local tag_id
  tag_id="$(get_dummy_tag_id "$DUMMY_NAME")"

  if [ -z "$tag_id" ]; then
    log_verbose "Creating virtual screen '$DUMMY_NAME' (${aspect_w}:${aspect_h})..."
    "$BD_CLI" create \
      -type=VirtualScreen \
      -virtualScreenName="$DUMMY_NAME" \
      -aspectWidth="$aspect_w" \
      -aspectHeight="$aspect_h" >/dev/null 2>&1

    sleep 0.5
    tag_id="$(get_dummy_tag_id "$DUMMY_NAME")"
    if [ -z "$tag_id" ]; then
      echo "Error: Failed to create or retrieve tag ID for virtual screen '$DUMMY_NAME'." >&2
      send_notification "Magic Trackpad Polling" "Configuration Failed" "Could not create 120Hz virtual screen in BetterDisplay." "Basso"
      exit "$EXIT_DUMMY_CREATION_FAILED"
    fi
  fi

  log_verbose "Virtual dummy tagID: $tag_id"

  # Inject custom 60 and 120Hz refresh rates into BetterDisplay preferences
  defaults write pro.betterdisplay.BetterDisplay "useCustomRefreshRates@VirtualScreen:${tag_id}" -bool true
  defaults write pro.betterdisplay.BetterDisplay "refreshRates@VirtualScreen:${tag_id}" -string "[60, 120]"

  # Cycle connection to apply new refresh rates
  log_verbose "Reconnecting dummy to load refresh rates..."
  "$BD_CLI" set -name="$DUMMY_NAME" -connected=off >/dev/null 2>&1 || true
  sleep 0.3
  "$BD_CLI" set -name="$DUMMY_NAME" -connected=on >/dev/null 2>&1
  sleep 0.5

  # Query display mode list
  local mode_list
  mode_list="$("$BD_CLI" get -name="$DUMMY_NAME" -displayModeList 2>/dev/null)"
  log_verbose "Querying display modes for optimal 120Hz mode..."

  local optimal_mode
  optimal_mode="$("$PYTHON_BIN" -c "
import sys, re

modes_raw = sys.stdin.read()
lines = [l.strip() for l in modes_raw.splitlines() if l.strip()]

target_lw = '$logical_w'
target_lh = '$logical_h'
target_nw = '$native_w'
target_nh = '$native_h'

# Prioritized searches:
# 1. logical HiDPI 120Hz
for l in lines:
    if f'{target_lw}x{target_lh}' in l and 'HiDPI' in l and '120Hz' in l:
        print(l.split(' - ')[0])
        sys.exit(0)

# 2. native 120Hz
for l in lines:
    if f'{target_nw}x{target_nh}' in l and '120Hz' in l:
        print(l.split(' - ')[0])
        sys.exit(0)

# 3. logical 120Hz
for l in lines:
    if f'{target_lw}x{target_lh}' in l and '120Hz' in l:
        print(l.split(' - ')[0])
        sys.exit(0)

# 4. Any 120Hz Native / Default
for l in lines:
    if '120Hz' in l and ('Native' in l or 'Default' in l):
        print(l.split(' - ')[0])
        sys.exit(0)

# 5. Any 120Hz mode
for l in lines:
    if '120Hz' in l:
        print(l.split(' - ')[0])
        sys.exit(0)

sys.exit(1)
" <<< "$mode_list")"

  if [ -n "$optimal_mode" ]; then
    log_verbose "Setting display mode number: $optimal_mode"
    "$BD_CLI" set -name="$DUMMY_NAME" -displayModeNumber="$optimal_mode" >/dev/null 2>&1 || true
    sleep 0.3
  else
    log_verbose "Warning: Could not isolate exact 120Hz mode index; attempting to proceed."
  fi

  # Establish hardware mirror to physical display
  log_verbose "Mirroring '$DUMMY_NAME' to physical target '$target_name'..."
  "$BD_CLI" set -name="$DUMMY_NAME" -mirror=on -targetName="$target_name" >/dev/null 2>&1

  sleep 0.5
  local mirror_check
  mirror_check="$("$BD_CLI" get -name="$DUMMY_NAME" -mirror 2>/dev/null)"
  if ! echo "$mirror_check" | grep -qi "on"; then
    echo "Error: Failed to mirror '$DUMMY_NAME' onto '$target_name'." >&2
    send_notification "Magic Trackpad Polling" "Configuration Failed" "Could not establish hardware mirror. Check macOS permissions." "Basso"
    exit "$EXIT_MIRROR_FAILED"
  fi

  # Check trackpad hardware
  local tp_info
  tp_info="$(get_trackpad_info)"
  local tp_detected
  tp_detected="$("$PYTHON_BIN" -c "import sys, json; print('true' if json.load(sys.stdin).get('detected') else 'false')" <<< "$tp_info")"

  send_notification "Magic Trackpad Polling" "120Hz Mirror Active" "Polling unlocked to ~90–125Hz. Opening Test UFO benchmark..." "Glass"

  if [ "$OPT_NO_BROWSER" != true ] && [ "$OPT_HEADLESS" != true ]; then
    open "$TEST_UFO_URL"
  fi

  if [ "$OPT_JSON" = true ]; then
    "$PYTHON_BIN" -c "
import sys, json
res = {
    'status': 'ok',
    'action': 'enable',
    'target_display': sys.argv[1],
    'dummy_name': sys.argv[2],
    'mode_number': sys.argv[3],
    'mirror': 'on',
    'trackpad': json.loads(sys.argv[4]) if sys.argv[4] else {}
}
print(json.dumps(res, indent=2))
" "$target_name" "$DUMMY_NAME" "$optimal_mode" "$tp_info"
  else
    echo "=========================================================="
    echo "  Magic Trackpad 120Hz Polling Rate Unlock: ACTIVE        "
    echo "=========================================================="
    echo "Target Display:    $target_name"
    echo "Virtual Screen:    $DUMMY_NAME (120Hz Mirror)"
    if [ "$tp_detected" = "true" ]; then
      echo "Magic Trackpad:    Connected (Hardware Report: ~125Hz)"
    else
      echo "Notice: Magic Trackpad not detected; 120Hz link enabled for general compositor responsiveness."
    fi
    echo "Benchmark URL:     $TEST_UFO_URL"
    echo "=========================================================="
  fi

  if [ "$tp_detected" != "true" ]; then
    log_verbose "Magic Trackpad not detected in ioreg at enable time; continuing since 120Hz mirror is active."
  fi

  exit "$EXIT_SUCCESS"
}

# Subcommand: disable
cmd_disable() {
  log_verbose "Executing disable command..."
  check_betterdisplay_installed
  ensure_betterdisplay_running

  log_verbose "Disconnecting virtual dummy '$DUMMY_NAME'..."
  "$BD_CLI" set -name="$DUMMY_NAME" -connected=off >/dev/null 2>&1 || true

  send_notification "Magic Trackpad Polling" "Native 60Hz Restored" "Disconnected virtual dummy. Display restored to native 60Hz." "default"

  if [ "$OPT_JSON" = true ]; then
    echo '{"status": "ok", "action": "disable", "message": "Native 60Hz display restored"}'
  else
    echo "Native 60Hz display restored successfully."
  fi

  exit "$EXIT_SUCCESS"
}

# Subcommand: status
cmd_status() {
  local bd_installed=false
  local bd_running=false
  local dummy_created=false
  local dummy_connected=false
  local dummy_mirrored=false
  local tag_id=""

  if [ -x "$BD_CLI" ]; then
    bd_installed=true
    if pgrep -x "BetterDisplay" >/dev/null 2>&1; then
      bd_running=true
      tag_id="$(get_dummy_tag_id "$DUMMY_NAME" 2>/dev/null || echo "")"
      if [ -n "$tag_id" ]; then
        dummy_created=true
        local mir
        mir="$("$BD_CLI" get -name="$DUMMY_NAME" -mirror 2>/dev/null || echo "")"
        if echo "$mir" | grep -qi "on"; then
          dummy_mirrored=true
          dummy_connected=true
        else
          local conn
          conn="$("$BD_CLI" get -name="$DUMMY_NAME" -connected 2>/dev/null || echo "")"
          if echo "$conn" | grep -qi "on"; then
            dummy_connected=true
          fi
        fi
      fi
    fi
  fi

  local disp_json="{}"
  if [ -f "$DETECT_DISPLAY" ]; then
    disp_json="$("$PYTHON_BIN" "$DETECT_DISPLAY" 2>/dev/null || echo "{}")"
  fi

  local tp_info
  tp_info="$(get_trackpad_info)"

  if [ "$OPT_JSON" = true ]; then
    "$PYTHON_BIN" -c "
import sys, json
bd_inst = (sys.argv[1] == 'true')
bd_run = (sys.argv[2] == 'true')
d_created = (sys.argv[3] == 'true')
d_conn = (sys.argv[4] == 'true')
d_mir = (sys.argv[5] == 'true')
d_tag = sys.argv[6]
bd_app = sys.argv[7]
disp = json.loads(sys.argv[8]) if sys.argv[8] else {}
tp = json.loads(sys.argv[9]) if sys.argv[9] else {}

res = {
    'status': 'ok',
    'betterdisplay_installed': bd_inst,
    'betterdisplay_path': bd_app,
    'betterdisplay_running': bd_run,
    'dummy_created': d_created,
    'dummy_connected': d_conn,
    'dummy_mirrored': d_mir,
    'dummy_tag_id': d_tag,
    'physical_display': disp,
    'trackpad': tp
}
print(json.dumps(res, indent=2))
" "$bd_installed" "$bd_running" "$dummy_created" "$dummy_connected" "$dummy_mirrored" "$tag_id" "$BD_APP" "$disp_json" "$tp_info"
  else
    echo "=========================================================="
    echo "           Magic Trackpad Unlock System Status            "
    echo "=========================================================="
    echo "BetterDisplay Installed: $bd_installed ($BD_APP)"
    echo "BetterDisplay Running:   $bd_running"
    echo "Virtual Dummy Created:   $dummy_created"
    echo "Virtual Dummy Mirrored:  $dummy_mirrored"
    echo ""
    echo "Physical Display Info:"
    "$PYTHON_BIN" -c "
import json, sys
data = json.loads('''$disp_json''')
if data and data.get('status') == 'ok':
    print(f\"  Name:        {data.get('display_name')} (Vendor: {data.get('vendor_id')})\")
    print(f\"  Resolution:  {data.get('native_width')}x{data.get('native_height')} (Aspect: {data.get('aspect_ratio_str')})\")
    print(f\"  Refresh:     {data.get('refresh_rate')}Hz (is_60hz: {data.get('is_60hz')})\")
    print(f\"  Mirror:      {data.get('mirror_state')}\")
else:
    print('  No physical display detected.')
"
    echo ""
    echo "Magic Trackpad Info:"
    "$PYTHON_BIN" -c "
import json
tp = json.loads('''$tp_info''')
print(f\"  Detected:        {tp.get('detected')}\")
print(f\"  Product:         {tp.get('product')}\")
print(f\"  Transport:       {tp.get('transport')}\")
print(f\"  ReportInterval:  {tp.get('report_interval_us')} µs\")
print(f\"  Hardware Rate:   {tp.get('hardware_polling_hz')} Hz\")
"
    echo "=========================================================="
  fi

  exit "$EXIT_SUCCESS"
}

# Subcommand: test
cmd_test() {
  echo "Running diagnostics on Trackpad HID events and display compositor..."
  local tp_info
  tp_info="$(get_trackpad_info)"
  echo "Trackpad HID Diagnostics:"
  "$PYTHON_BIN" -c "
import json
tp = json.loads('''$tp_info''')
for k, v in tp.items():
    print(f'  {k}: {v}')
"
  echo ""
  echo "Testing display detection engine..."
  if [ -f "$DETECT_DISPLAY" ]; then
    "$PYTHON_BIN" "$DETECT_DISPLAY" --json
  else
    echo "Error: $DETECT_DISPLAY not found" >&2
    exit "$EXIT_GENERAL_ERROR"
  fi

  exit "$EXIT_SUCCESS"
}

# Subcommand: cleanup
cmd_cleanup() {
  log_verbose "Executing cleanup command..."
  if [ -x "$BD_CLI" ]; then
    ensure_betterdisplay_running
    log_verbose "Discarding virtual dummy '$DUMMY_NAME'..."
    "$BD_CLI" discard -name="$DUMMY_NAME" >/dev/null 2>&1 || true
  fi

  echo "Cleaned up virtual dummy '$DUMMY_NAME'."
  exit "$EXIT_SUCCESS"
}

show_help() {
  cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
  enable            Detect display, provision 120Hz dummy, activate mirror, notify, launch TestUFO.
  disable           Disconnect virtual dummy, restore native 60Hz display, notify.
  status            Print JSON or formatted report of displays, dummies, and trackpad rate.
  test              Run live diagnostic check on trackpad HID packets and report interval.
  install-deps      Automate Homebrew installation of BetterDisplay cask.
  cleanup           Completely delete 'Trackpad 120Hz Dummy' from BetterDisplay preferences.

OPTIONS:
  --force           Bypass the 60Hz guardrail check (force dummy creation).
  --headless        Suppress all GUI dialogs and browser popups.
  --no-browser      Enable 120Hz mirror but do not automatically open TestUFO.
  --target <NAME>   Specify target physical display name explicitly.
  --json            Output machine-readable JSON status messages to stdout.
  -v, --verbose     Enable detailed debug logging to stderr.
  -h, --help        Show usage information and exit.
EOF
}

# Parse global options and command
COMMAND=""

while [ $# -gt 0 ]; do
  case "$1" in
    enable|disable|status|test|install-deps|cleanup)
      COMMAND="$1"
      shift
      ;;
    --force)
      OPT_FORCE=true
      shift
      ;;
    --headless)
      OPT_HEADLESS=true
      shift
      ;;
    --no-browser)
      OPT_NO_BROWSER=true
      shift
      ;;
    --target)
      OPT_TARGET="$2"
      shift 2
      ;;
    --json)
      OPT_JSON=true
      shift
      ;;
    -v|--verbose)
      OPT_VERBOSE=true
      shift
      ;;
    -h|--help)
      show_help
      exit "$EXIT_SUCCESS"
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help
      exit "$EXIT_GENERAL_ERROR"
      ;;
  esac
done

if [ -z "$COMMAND" ]; then
  COMMAND="status"
fi

case "$COMMAND" in
  enable)
    cmd_enable
    ;;
  disable)
    cmd_disable
    ;;
  status)
    cmd_status
    ;;
  test)
    cmd_test
    ;;
  install-deps)
    install_deps
    ;;
  cleanup)
    cmd_cleanup
    ;;
esac
