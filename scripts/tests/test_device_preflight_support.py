"""Deterministic tests for the static device-preflight table (no device required)."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from device_preflight_support import classify_ios_version, xcode_ios_range


class DevicePreflightSupportTests(unittest.TestCase):
    def test_maximum_xcode_major_is_not_an_ios_patch_or_minor_ceiling(self):
        for ios in ("27.0", "27.0.1", "27.1"):
            with self.subTest(ios=ios):
                self.assertEqual(classify_ios_version(ios, "17-27"), "NOT_DETERMINED")

    def test_versions_below_maximum_major_are_only_table_indications(self):
        self.assertEqual(classify_ios_version("26.5", "17-27"), "IN_TABLE")
        self.assertEqual(classify_ios_version("17", "17-27"), "IN_TABLE")

    def test_versions_older_than_the_listed_interval_are_not_called_incompatible(self):
        self.assertEqual(classify_ios_version("16.7.1", "17-27"), "OUTSIDE_TABLE")

    def test_malformed_versions_fail_closed(self):
        for ios in ("", "27.0.1beta", "27..1", "v27.0"):
            with self.subTest(ios=ios):
                self.assertEqual(classify_ios_version(ios, "17-27"), "INVALID")
        self.assertIsNone(xcode_ios_range("27.x"))

    def test_only_existing_xcode_major_rows_are_returned(self):
        self.assertEqual(xcode_ios_range("26.2"), "15-26.5")
        self.assertEqual(xcode_ios_range("27.2"), "17-27")
        for xcode in ("25.4", "28.0"):
            with self.subTest(xcode=xcode):
                row = xcode_ios_range(xcode)
                self.assertIsNone(row)
                self.assertEqual(classify_ios_version("27.0.1", row), "NOT_DETERMINED")

    def test_maximum_major_for_xcode_26_is_also_unresolved(self):
        self.assertEqual(classify_ios_version("26.5", "15-26.5"), "NOT_DETERMINED")


if __name__ == "__main__":
    unittest.main()
