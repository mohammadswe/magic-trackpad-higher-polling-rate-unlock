#!/usr/bin/env python3
"""Display Detection and Profiling Engine for Magic Trackpad Polling Unlock.

Extracts physical display metrics from macOS system_profiler SPDisplaysDataType JSON,
filters out virtual screens/dummies, inspects active mirror topologies, and evaluates
refresh rate guardrails.
"""

import argparse
import json
import math
import re
import subprocess
import sys


def is_dummy_display(disp):
    """Check if display entry is a virtual screen / dummy."""
    name = disp.get("_name", "").strip()
    name_lower = name.lower()

    # Vendor ID check: BetterDisplay uses 0x896 (hex) / 2198 (dec)
    vendor_raw = str(disp.get("_spdisplays_display-vendor-id", "")).strip().lower()
    if vendor_raw:
        clean_vendor = vendor_raw.lstrip("0x")
        if clean_vendor in ("896", "2198", "0896"):
            return True
        try:
            val = int(vendor_raw, 0)
            if val in (0x896, 2198):
                return True
        except ValueError:
            pass

    # Name patterns for known dummies / virtual screens
    dummy_patterns = [
        "dummy",
        "virtual",
        "16:10 display",
        "3:2 display",
        "5k 120hz dummy",
        "trackpad 120hz dummy",
    ]
    for pattern in dummy_patterns:
        if pattern in name_lower:
            return True

    return False


def parse_refresh_rate(res_str, refresh_field=None):
    """Parse refresh rate from resolution string or refresh rate field."""
    if refresh_field:
        m = re.search(r"(\d+(?:\.\d+)?)", str(refresh_field))
        if m:
            val = float(m.group(1))
            return int(round(val)) if abs(val - round(val)) < 0.05 else val

    if res_str:
        # e.g. "2560 x 1440 @ 60.00Hz", "1920 x 1080 @ 120Hz"
        m = re.search(r"@\s*(\d+(?:\.\d+)?)\s*Hz", res_str, re.IGNORECASE)
        if m:
            val = float(m.group(1))
            return int(round(val)) if abs(val - round(val)) < 0.05 else val

    return 60


def parse_dimensions(disp):
    """Extract native and logical display dimensions."""
    native_w, native_h = 0, 0
    logical_w, logical_h = 0, 0

    # Native resolution parsing:
    # 1. spdisplays_pixelresolution (e.g. "spdisplays_5120x2880Retina2" or "3840 x 2160")
    pixel_res_str = disp.get("spdisplays_pixelresolution", "")
    if pixel_res_str:
        m = re.search(r"(\d{3,5})\s*x\s*(\d{3,5})", pixel_res_str)
        if m:
            native_w = int(m.group(1))
            native_h = int(m.group(2))

    # 2. _spdisplays_pixels (e.g. "5120 x 2880")
    if not (native_w and native_h):
        pixels_str = disp.get("_spdisplays_pixels", "")
        if pixels_str:
            m = re.search(r"(\d{3,5})\s*x\s*(\d{3,5})", pixels_str)
            if m:
                native_w = int(m.group(1))
                native_h = int(m.group(2))

    # Logical resolution parsing:
    res_str = disp.get("_spdisplays_resolution", "")
    if res_str:
        m = re.search(r"(\d{3,5})\s*x\s*(\d{3,5})", res_str)
        if m:
            logical_w = int(m.group(1))
            logical_h = int(m.group(2))

    if not (logical_w and logical_h) and (native_w and native_h):
        # Default logical to half native if Retina, or native if standard
        if "retina" in disp.get("spdisplays_display_type", "").lower() or (
            pixel_res_str and "retina" in pixel_res_str.lower()
        ):
            logical_w = native_w // 2
            logical_h = native_h // 2
        else:
            logical_w = native_w
            logical_h = native_h

    if not (native_w and native_h):
        native_w = logical_w or 2560
        native_h = logical_h or 1440

    return native_w, native_h, logical_w, logical_h


def compute_aspect_ratio(width, height):
    """Calculate reduced aspect ratio and normalized aspect ratio string."""
    if width <= 0 or height <= 0:
        return 16, 9, "16:9"

    g = math.gcd(width, height)
    rw = width // g
    rh = height // g

    # Standard normalization mappings
    # 16:9
    if (rw, rh) == (16, 9):
        return 16, 9, "16:9"

    # 16:10 (8:5 reduced)
    if (rw, rh) in ((16, 10), (8, 5)):
        return 16, 10, "16:10"

    # 3:2
    if (rw, rh) == (3, 2):
        return 3, 2, "3:2"

    # 21:9 UltraWide (typically 43:18 or 64:27 or ratio ~ 2.37 - 2.4)
    if (rw, rh) in ((43, 18), (64, 27), (21, 9)):
        return rw, rh, "21:9"
    ratio = width / height
    if 2.30 <= ratio <= 2.45:
        return rw, rh, "21:9"

    # 32:9 Super UltraWide
    if (rw, rh) == (32, 9) or 3.50 <= ratio <= 3.60:
        return 32, 9, "32:9"

    # 4:3
    if (rw, rh) == (4, 3):
        return 4, 3, "4:3"

    # MacBook Pro notched screen ratio (~1.54) -> maps logically to 16:10
    if 1.50 <= ratio <= 1.62:
        return 16, 10, "16:10"

    return rw, rh, f"{rw}:{rh}"


def extract_displays_from_profiler_json(json_data):
    """Extract physical displays list from system_profiler JSON structure."""
    items = json_data.get("SPDisplaysDataType", [])
    if isinstance(items, dict):
        items = [items]

    physical_displays = []
    dummy_displays = []

    for item in items:
        ndrvs = item.get("spdisplays_ndrvs", [])
        if isinstance(ndrvs, dict):
            ndrvs = [ndrvs]

        for disp in ndrvs:
            if is_dummy_display(disp):
                dummy_displays.append(disp)
            else:
                physical_displays.append(disp)

    return physical_displays, dummy_displays


def profile_display(disp):
    """Extract standardized metrics dictionary from physical display entry."""
    name = disp.get("_name", "Unknown Display").strip()
    is_builtin = disp.get("spdisplays_builtin", "").lower() == "spdisplays_yes"

    res_str = disp.get("_spdisplays_resolution", "")
    refresh_rate = parse_refresh_rate(
        res_str, disp.get("spdisplays_refresh_rate")
    )
    is_60hz = refresh_rate <= 75.0
    is_high_refresh = refresh_rate >= 100.0

    native_w, native_h, logical_w, logical_h = parse_dimensions(disp)
    aspect_w, aspect_h, aspect_ratio_str = compute_aspect_ratio(
        native_w, native_h
    )

    mirror_status_raw = disp.get("spdisplays_mirror_status", "")
    if "hardware_mirror" in mirror_status_raw:
        mirror_state = "hardware_mirror"
    elif "master_mirror" in mirror_status_raw:
        mirror_state = "master_mirror"
    else:
        mirror_state = "none"

    vendor_raw = str(disp.get("_spdisplays_display-vendor-id", "")).strip()
    if vendor_raw:
        if not vendor_raw.startswith("0x"):
            vendor_id = f"0x{int(vendor_raw, 16):04x}" if all(c in "0123456789abcdefABCDEF" for c in vendor_raw) else f"0x{vendor_raw}"
        else:
            vendor_id = vendor_raw
    else:
        vendor_id = "0x0000"

    raw_res = res_str or f"{native_w} x {native_h} @ {refresh_rate:.2f}Hz"

    return {
        "status": "ok",
        "display_name": name,
        "is_builtin": is_builtin,
        "refresh_rate": refresh_rate,
        "is_60hz": is_60hz,
        "is_high_refresh": is_high_refresh,
        "native_width": native_w,
        "native_height": native_h,
        "logical_width": logical_w,
        "logical_height": logical_h,
        "aspect_w": aspect_w,
        "aspect_h": aspect_h,
        "aspect_ratio_str": aspect_ratio_str,
        "mirror_state": mirror_state,
        "vendor_id": vendor_id,
        "raw_resolution_str": raw_res,
    }


def select_target_display(physical_displays, target_name=None):
    """Select target physical display based on name or heuristic."""
    if not physical_displays:
        return None

    # If explicit target name provided
    if target_name:
        target_name_clean = target_name.strip().lower()
        for disp in physical_displays:
            if target_name_clean in disp.get("_name", "").lower():
                return disp

    # Multi-monitor heuristic:
    # If there's an external 60Hz display paired with a built-in display, prefer external 60Hz
    external_60hz = []
    for disp in physical_displays:
        is_builtin = disp.get("spdisplays_builtin", "").lower() == "spdisplays_yes"
        res_str = disp.get("_spdisplays_resolution", "")
        rate = parse_refresh_rate(res_str, disp.get("spdisplays_refresh_rate"))
        if not is_builtin and rate <= 75:
            external_60hz.append(disp)

    if external_60hz:
        # Prefer main display among external 60Hz displays if specified
        for disp in external_60hz:
            if disp.get("spdisplays_main", "").lower() == "spdisplays_yes":
                return disp
        return external_60hz[0]

    # Otherwise prefer main display
    for disp in physical_displays:
        if disp.get("spdisplays_main", "").lower() == "spdisplays_yes":
            return disp

    # Fallback to first physical display
    return physical_displays[0]


def get_system_profiler_json():
    """Execute system_profiler SPDisplaysDataType -json and parse result."""
    cmd = ["/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"]
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        return json.loads(proc.stdout)
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"Error running system_profiler: {e}\n")
        return None
    except json.JSONDecodeError as e:
        sys.stderr.write(f"Error parsing system_profiler JSON: {e}\n")
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Display Profiler and Guardrail Engine for Magic Trackpad Polling Unlock"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        default=True,
        help="Output complete display metrics as formatted JSON (default)",
    )
    parser.add_argument(
        "--field",
        metavar="FIELD_NAME",
        help="Output only the specific field value (e.g. refresh_rate, display_name, aspect_w)",
    )
    parser.add_argument(
        "--target-name",
        metavar="NAME",
        help="Filter by specific physical display name",
    )
    parser.add_argument(
        "--check-guardrail",
        action="store_true",
        help="Exit code 0 if primary display is <= 75Hz; exit code 2 if already >= 100Hz",
    )
    parser.add_argument(
        "--file",
        metavar="PATH",
        help="Load display JSON from file instead of running system_profiler (for testing)",
    )
    parser.add_argument(
        "--stdin",
        action="store_true",
        help="Load display JSON from standard input",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Print raw parsed display trees to stderr for troubleshooting",
    )

    args = parser.parse_args()

    # Load data
    if args.stdin:
        try:
            json_data = json.load(sys.stdin)
        except Exception as e:
            sys.stderr.write(f"Error reading JSON from stdin: {e}\n")
            sys.exit(1)
    elif args.file:
        try:
            with open(args.file, "r", encoding="utf-8") as f:
                json_data = json.load(f)
        except Exception as e:
            sys.stderr.write(f"Error reading file '{args.file}': {e}\n")
            sys.exit(1)
    else:
        json_data = get_system_profiler_json()

    if not json_data:
        err = {"status": "error", "message": "Failed to obtain SPDisplaysDataType JSON"}
        if args.json and not args.field:
            print(json.dumps(err, indent=2))
        else:
            sys.stderr.write("Failed to obtain SPDisplaysDataType JSON\n")
        sys.exit(1)

    physical_displays, dummy_displays = extract_displays_from_profiler_json(json_data)

    if args.debug:
        sys.stderr.write(
            f"Debug: Found {len(physical_displays)} physical displays, {len(dummy_displays)} dummy displays.\n"
        )
        for i, d in enumerate(physical_displays):
            sys.stderr.write(
                f"  Physical[{i}]: {d.get('_name')} (vendor: {d.get('_spdisplays_display-vendor-id')})\n"
            )
        for i, d in enumerate(dummy_displays):
            sys.stderr.write(
                f"  Dummy[{i}]: {d.get('_name')} (vendor: {d.get('_spdisplays_display-vendor-id')})\n"
            )

    selected_raw = select_target_display(physical_displays, args.target_name)

    if not selected_raw:
        err = {
            "status": "error",
            "message": "No active physical display found (all candidates were dummy displays or empty)",
        }
        if args.field:
            sys.exit(1)
        print(json.dumps(err, indent=2))
        sys.exit(1)

    profile = profile_display(selected_raw)

    if args.field:
        if args.field in profile:
            val = profile[args.field]
            if isinstance(val, bool):
                print("true" if val else "false")
            else:
                print(val)
        else:
            sys.stderr.write(f"Field '{args.field}' not found in profile\n")
            sys.exit(1)
    else:
        print(json.dumps(profile, indent=2))

    # Guardrail evaluation
    if args.check_guardrail:
        if profile["is_high_refresh"]:
            # Display is already >= 100Hz
            sys.exit(2)
        elif profile["is_60hz"]:
            # Display is qualified (<= 75Hz)
            sys.exit(0)
        else:
            # Between 76Hz and 99Hz: not high refresh, proceed
            sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    main()
