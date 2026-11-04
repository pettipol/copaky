"""Copaky: exercise the runner's pure-local install-bypass gate; no Apple tools or devices."""
from __future__ import annotations

import copy
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1]
RUNNER = SCRIPTS / "memory_phase_c.sh"
# Execute exactly the embedded preflight, independently of the device execution lane.
PREFLIGHT = RUNNER.read_text().split("<<'PYPREPARED'\n", 1)[1].split("\nPYPREPARED\n", 1)[0]


class PreparedInputsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "azooKey.app"
        for folder, bundle, executable in (
            (self.app, "com.pettipol.copaky", "azooKey"),
            (self.app / "PlugIns/Keyboard.appex", "com.pettipol.copaky.keyboard", "Keyboard"),
        ):
            folder.mkdir(parents=True)
            (folder / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": bundle, "CFBundleExecutable": executable,
                "CFBundleVersion": "10", "CFBundleShortVersionString": "0.1",
            }))
            (folder / executable).write_bytes(b"synthetic executable")
        self.target = {"BlueprintName": "azooKeyUITests", "UseDestinationArtifacts": True,
                       "TestHostBundleIdentifier": "com.pettipol.copaky.uitests.xctrunner",
                       "UITargetAppBundleIdentifier": "com.pettipol.copaky",
                       "TestBundleDestinationRelativePath": "__TESTHOST__/PlugIns/azooKeyUITests.xctest"}

    def preflight(self, document, baseline=None):
        run = self.root / "prepared.xctestrun"
        run.write_bytes(plistlib.dumps(document))
        output = self.root / "manifest.json"
        output.unlink(missing_ok=True)
        args = [sys.executable, "-", str(SCRIPTS), str(run), str(self.app), str(output)]
        if baseline is not None:
            args.append(str(baseline))
        result = subprocess.run(args,
                                input=PREFLIGHT, capture_output=True, text=True,
                                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        return result, output

    def freeze(self):
        result, output = self.preflight({"azooKeyUITests": self.target})
        self.assertEqual(result.returncode, 0, result.stderr)
        baseline = self.root / "frozen.json"
        baseline.write_bytes(output.read_bytes())
        return baseline

    def assert_changed_inputs_rejected(self, baseline):
        result, output = self.preflight({"azooKeyUITests": self.target}, baseline)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("prepared inputs changed", result.stderr)
        self.assertFalse(output.exists(), "changed inputs must not produce a successful postflight receipt")

    def test_postflight_rejects_dictionary_resource_mutation_with_unchanged_executables(self):
        resource = self.app / "dictionary.dat"
        resource.write_bytes(b"original dictionary")
        baseline = self.freeze()
        resource.write_bytes(b"modified dictionary")
        self.assert_changed_inputs_rejected(baseline)

    def test_postflight_rejects_extension_privacy_flag_mutation(self):
        info = self.app / "PlugIns/Keyboard.appex/Info.plist"
        document = plistlib.loads(info.read_bytes())
        document["NSExtension"] = {"NSExtensionAttributes": {"RequestsOpenAccess": False}}
        info.write_bytes(plistlib.dumps(document))
        baseline = self.freeze()
        document["NSExtension"]["NSExtensionAttributes"]["RequestsOpenAccess"] = True
        info.write_bytes(plistlib.dumps(document))
        self.assert_changed_inputs_rejected(baseline)

    def test_postflight_rejects_added_and_deleted_resources(self):
        resource = self.app / "dictionary.dat"
        baseline = self.freeze()
        resource.write_bytes(b"new dictionary")
        self.assert_changed_inputs_rejected(baseline)
        baseline = self.freeze()
        resource.unlink()
        self.assert_changed_inputs_rejected(baseline)

    def test_postflight_rejects_permission_and_symlink_target_changes(self):
        resource = self.app / "dictionary.dat"
        resource.write_bytes(b"dictionary")
        baseline = self.freeze()
        resource.chmod(0o400)
        self.assert_changed_inputs_rejected(baseline)
        link = self.app / "dictionary-link"
        link.symlink_to("dictionary.dat")
        baseline = self.freeze()
        link.unlink()
        link.symlink_to("Info.plist")
        self.assert_changed_inputs_rejected(baseline)

    def test_unchanged_bundle_passes_postflight_and_external_link_fails_closed(self):
        baseline = self.freeze()
        result, _ = self.preflight({"azooKeyUITests": self.target}, baseline)
        self.assertEqual(result.returncode, 0, result.stderr)
        outside = self.root / "outside"
        outside.write_bytes(b"not frozen")
        (self.app / "external-link").symlink_to(outside)
        result, _ = self.preflight({"azooKeyUITests": self.target})
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("symlink escapes", result.stderr)

    def test_v1_v2_destination_only_inputs_record_local_identity(self):
        for document in ({"azooKeyUITests": self.target},
                         {"TestConfigurations": [{"TestTargets": [self.target]}]}):
            with self.subTest(document=document):
                result, output = self.preflight(document)
                self.assertEqual(result.returncode, 0, result.stderr)
                manifest = json.loads(output.read_text())
                self.assertEqual(manifest["installed_binary_hash"], "NOT_VERIFIED")
                self.assertEqual(manifest["configuration_source"], "caller_declared_Release")
                self.assertEqual(len(manifest["xctestrun_sha256"]), 64)
                self.assertEqual(len(manifest["artifact"]["extension"]["binary_sha256"]), 64)

    def test_missing_false_wrong_identity_or_local_install_path_cannot_bypass_install(self):
        mutations = []
        for key in self.target:
            target = copy.deepcopy(self.target)
            del target[key]
            mutations.append(target)
        for key, value in (("UseDestinationArtifacts", False), ("UseDestinationArtifacts", "true"),
                           ("TestHostBundleIdentifier", "wrong.runner"),
                           ("UITargetAppBundleIdentifier", "wrong.app"),
                           ("TestBundleDestinationRelativePath", "../other.xctest"),
                           ("TestBundlePath", "/local/test.xctest")):
            target = {**self.target, key: value}
            mutations.append(target)
        for target in mutations:
            with self.subTest(target=target):
                result, output = self.preflight({"TestConfigurations": [{"TestTargets": [target]}]})
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(output.exists(), "rejected inputs must not produce an identity receipt")

    def test_extra_target_or_wrong_app_is_rejected(self):
        result, _ = self.preflight({"TestConfigurations": [{"TestTargets": [self.target, self.target]}]})
        self.assertEqual(result.returncode, 2)
        info = self.app / "Info.plist"
        document = plistlib.loads(info.read_bytes())
        document["CFBundleIdentifier"] = "wrong.app"
        info.write_bytes(plistlib.dumps(document))
        result, _ = self.preflight({"azooKeyUITests": self.target})
        self.assertEqual(result.returncode, 2)

    def test_partial_flags_relative_or_existing_output_fail_before_tools(self):
        for flags in (["--prepared-app", str(self.app)],
                      ["--prepared-app", str(self.app), "--prepared-xctestrun", "missing.xctestrun", "--out", "relative"],
                      ["--prepared-app", str(self.app), "--prepared-xctestrun", "missing.xctestrun", "--out", str(self.root)]):
            result = subprocess.run(["bash", str(RUNNER), "--mode", "device", *flags],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("ERROR:", result.stderr)


if __name__ == "__main__":
    unittest.main()
