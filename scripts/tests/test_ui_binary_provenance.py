"""Copaky: compare app and keyboard binaries without a simulator."""
from __future__ import annotations

import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
HELPER = SCRIPTS / "ui_binary_provenance.py"


class UIBinaryProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.built = self.root / "built" / "Copaky.app"
        self.installed = self.root / "installed" / "Copaky.app"
        self._make_app(self.built)
        self._make_app(self.installed)

    @staticmethod
    def _write_bundle(bundle: Path, executable: str, contents: bytes,
                      *, debug: bytes | None = None) -> None:
        bundle.mkdir(parents=True, exist_ok=True)
        (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": executable}))
        (bundle / executable).write_bytes(contents)
        debug_path = bundle / f"{executable}.debug.dylib"
        if debug is not None:
            debug_path.write_bytes(debug)
        elif debug_path.exists():
            debug_path.unlink()

    @classmethod
    def _make_app(cls, app: Path, *, main: bytes = b"main-v1",
                  extension: bytes = b"keyboard-v1", main_debug: bytes | None = None,
                  extension_debug: bytes | None = None) -> None:
        cls._write_bundle(app, "Copaky", main, debug=main_debug)
        cls._write_bundle(app / "PlugIns" / "Keyboard.appex", "Keyboard", extension,
                          debug=extension_debug)

    def _run(self, out: Path | None = None):
        receipt_path = out or self.root / "receipt.json"
        process = subprocess.run(
            [sys.executable, str(HELPER), str(self.built), str(self.installed),
             "--out", str(receipt_path)],
            capture_output=True, text=True, check=False,
        )
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
        return process, receipt

    def test_matching_main_extension_and_optional_debug_binaries_pass(self):
        self._make_app(self.built, main_debug=b"main-debug-v1", extension_debug=b"keyboard-debug-v1")
        self._make_app(self.installed, main_debug=b"main-debug-v1", extension_debug=b"keyboard-debug-v1")

        process, receipt = self._run()

        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(receipt["status"], "PASS")
        self.assertTrue(all(row["match"] for row in receipt["comparisons"]))
        components = {row["component"] for row in receipt["comparisons"]}
        self.assertIn("main_executable", components)
        self.assertIn("keyboard_extension_executable", components)
        self.assertTrue(all("/Users/" not in value for value in _all_strings(receipt)))
        self.assertTrue(all(not Path(value).is_absolute() for value in _product_paths(receipt)))

    def test_matching_bundles_without_debug_dylibs_pass(self):
        process, receipt = self._run()

        self.assertEqual(process.returncode, 0, process.stderr)
        debug_rows = [row for row in receipt["comparisons"] if row["component"].endswith("debug_dylib")]
        self.assertEqual(len(debug_rows), 2)
        self.assertTrue(all(row["match"] and not row["built"]["present"]
                            and not row["installed"]["present"] for row in debug_rows))

    def test_changed_main_executable_fails(self):
        self._make_app(self.installed, main=b"main-v2")

        process, receipt = self._run()

        self.assertEqual(process.returncode, 1)
        self.assertEqual(receipt["status"], "FAIL")
        main = next(row for row in receipt["comparisons"] if row["component"] == "main_executable")
        self.assertFalse(main["match"])

    def test_changed_keyboard_extension_executable_fails(self):
        self._make_app(self.installed, extension=b"keyboard-v2")

        process, receipt = self._run()

        self.assertEqual(process.returncode, 1)
        extension = next(row for row in receipt["comparisons"]
                         if row["component"] == "keyboard_extension_executable")
        self.assertFalse(extension["match"])

    def test_missing_required_binary_fails_closed(self):
        (self.installed / "PlugIns" / "Keyboard.appex" / "Keyboard").unlink()

        process, receipt = self._run()

        self.assertEqual(process.returncode, 1)
        self.assertEqual(receipt["status"], "FAIL")
        self.assertIn("missing_binary", json.dumps(receipt))

    def test_missing_bundle_or_plist_fails_closed(self):
        (self.installed / "Info.plist").unlink()
        process, receipt = self._run()
        self.assertEqual(process.returncode, 1)
        self.assertIn("missing_info_plist", json.dumps(receipt))

        self.installed.rename(self.root / "removed.app")
        process, receipt = self._run()
        self.assertEqual(process.returncode, 1)
        self.assertIn("missing_bundle", json.dumps(receipt))

    def test_malformed_info_plist_fails_closed(self):
        (self.installed / "Info.plist").write_bytes(b"not a plist")

        process, receipt = self._run()

        self.assertEqual(process.returncode, 1)
        self.assertEqual(receipt["status"], "FAIL")
        self.assertIn("unreadable_info_plist", json.dumps(receipt))

    def test_different_debug_dylib_presence_fails(self):
        self._make_app(self.built, main_debug=b"main-debug-v1")

        process, receipt = self._run()

        self.assertEqual(process.returncode, 1)
        debug = next(row for row in receipt["comparisons"]
                     if row["component"] == "main_debug_dylib")
        self.assertFalse(debug["match"])
        self.assertFalse(debug["presence_match"])

    def test_changed_debug_dylib_bytes_fail(self):
        self._make_app(self.built, extension_debug=b"keyboard-debug-built")
        self._make_app(self.installed, extension_debug=b"keyboard-debug-installed")

        process, receipt = self._run()

        self.assertEqual(process.returncode, 1)
        debug = next(row for row in receipt["comparisons"]
                     if row["component"] == "keyboard_extension_debug_dylib")
        self.assertFalse(debug["match"])
        self.assertTrue(debug["presence_match"])
        self.assertFalse(debug["content_match"])


def _all_strings(value):
    if isinstance(value, dict):
        for key, item in value.items():
            yield from _all_strings(key)
            yield from _all_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _all_strings(item)
    elif isinstance(value, str):
        yield value


def _product_paths(receipt):
    for row in receipt["comparisons"]:
        yield from row["relative_paths"].values()


if __name__ == "__main__":
    unittest.main()
