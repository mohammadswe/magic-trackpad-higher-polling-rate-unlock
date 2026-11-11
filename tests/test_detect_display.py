#!/usr/bin/env python3
"""Unit tests for detect-display.py display profiling and guardrail engine."""

import json
import os
import subprocess
import sys
import unittest

# Add bin directory to python path for direct function testing
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN_DIR = os.path.join(BASE_DIR, "bin")
FIXTURES_DIR = os.path.join(BASE_DIR, "tests", "fixtures")
sys.path.insert(0, BIN_DIR)

import importlib.util

spec = importlib.util.spec_from_file_location(
    "detect_display", os.path.join(BIN_DIR, "detect-display.py")
)
detect_display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detect_display)


class TestDisplayDetection(unittest.TestCase):
    """Test display detection, profiling, and guardrail verification."""

    def load_fixture(self, filename):
        path = os.path.join(FIXTURES_DIR, filename)
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    def test_studio_display_60hz(self):
        data = self.load_fixture("studio_display_60hz.json")
        physical, dummies = detect_display.extract_displays_from_profiler_json(data)
        self.assertEqual(len(physical), 1)
        self.assertEqual(len(dummies), 0)

        selected = detect_display.select_target_display(physical)
        self.assertIsNotNone(selected)
        profile = detect_display.profile_display(selected)

        self.assertEqual(profile["status"], "ok")
        self.assertEqual(profile["display_name"], "Studio Display")
        self.assertEqual(profile["refresh_rate"], 60)
        self.assertTrue(profile["is_60hz"])
        self.assertFalse(profile["is_high_refresh"])
        self.assertEqual(profile["aspect_w"], 16)
        self.assertEqual(profile["aspect_h"], 9)
        self.assertEqual(profile["aspect_ratio_str"], "16:9")

    def test_macbook_promotion_120hz(self):
        data = self.load_fixture("macbook_promotion_120hz.json")
        physical, dummies = detect_display.extract_displays_from_profiler_json(data)
        self.assertEqual(len(physical), 1)
        self.assertEqual(len(dummies), 0)

        selected = detect_display.select_target_display(physical)
        profile = detect_display.profile_display(selected)

        self.assertEqual(profile["refresh_rate"], 120)
        self.assertFalse(profile["is_60hz"])
        self.assertTrue(profile["is_high_refresh"])
        self.assertTrue(profile["is_builtin"])

    def test_dual_monitor_setup(self):
        data = self.load_fixture("dual_monitor_setup.json")
        physical, dummies = detect_display.extract_displays_from_profiler_json(data)
        self.assertEqual(len(physical), 2)

        # Default heuristic should pick external 60Hz Studio Display
        selected = detect_display.select_target_display(physical)
        self.assertEqual(selected.get("_name"), "Studio Display")
        profile = detect_display.profile_display(selected)
        self.assertEqual(profile["refresh_rate"], 60)
        self.assertTrue(profile["is_60hz"])

        # Target name filtering for built-in display
        targeted = detect_display.select_target_display(physical, target_name="Built-in")
        self.assertIn("Built-in", targeted.get("_name"))

    def test_active_mirror_setup(self):
        data = self.load_fixture("active_mirror_setup.json")
        physical, dummies = detect_display.extract_displays_from_profiler_json(data)

        # The 3:2 dummy (vendor 896) must be classified as dummy
        self.assertEqual(len(dummies), 1)
        self.assertIn("3:2", dummies[0].get("_name"))

        # The physical display must be Studio Display
        self.assertEqual(len(physical), 1)
        self.assertEqual(physical[0].get("_name"), "Studio Display")

        selected = detect_display.select_target_display(physical)
        profile = detect_display.profile_display(selected)
        self.assertEqual(profile["display_name"], "Studio Display")
        self.assertEqual(profile["refresh_rate"], 60)
        self.assertTrue(profile["is_60hz"])
        self.assertEqual(profile["aspect_ratio_str"], "16:9")

    def test_aspect_ratio_computations(self):
        # 16:9
        self.assertEqual(detect_display.compute_aspect_ratio(5120, 2880), (16, 9, "16:9"))
        self.assertEqual(detect_display.compute_aspect_ratio(3840, 2160), (16, 9, "16:9"))
        self.assertEqual(detect_display.compute_aspect_ratio(2560, 1440), (16, 9, "16:9"))
        self.assertEqual(detect_display.compute_aspect_ratio(1920, 1080), (16, 9, "16:9"))

        # 16:10
        self.assertEqual(detect_display.compute_aspect_ratio(2560, 1600), (16, 10, "16:10"))
        self.assertEqual(detect_display.compute_aspect_ratio(1920, 1200), (16, 10, "16:10"))

        # 3:2
        self.assertEqual(detect_display.compute_aspect_ratio(4320, 2880), (3, 2, "3:2"))
        self.assertEqual(detect_display.compute_aspect_ratio(3000, 2000), (3, 2, "3:2"))

        # 21:9
        rw, rh, s = detect_display.compute_aspect_ratio(3440, 1440)
        self.assertEqual(s, "21:9")
        rw, rh, s = detect_display.compute_aspect_ratio(5120, 2160)
        self.assertEqual(s, "21:9")

        # 32:9
        self.assertEqual(detect_display.compute_aspect_ratio(5120, 1440), (32, 9, "32:9"))

    def test_cli_execution_guardrails(self):
        script_path = os.path.join(BIN_DIR, "detect-display.py")

        # Studio display -> 0
        res = subprocess.run(
            [sys.executable, script_path, "--file", os.path.join(FIXTURES_DIR, "studio_display_60hz.json"), "--check-guardrail"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        self.assertEqual(res.returncode, 0)

        # MacBook Pro 120Hz -> 2
        res = subprocess.run(
            [sys.executable, script_path, "--file", os.path.join(FIXTURES_DIR, "macbook_promotion_120hz.json"), "--check-guardrail"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        self.assertEqual(res.returncode, 2)


if __name__ == "__main__":
    unittest.main()
