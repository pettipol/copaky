"""Copaky: exercise the actual seed generator without simctl or a real container."""
import json
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from uuid import UUID


class H55SyntheticSeedTests(unittest.TestCase):
    token = str(UUID(int=0xC0A5))

    def run_generator(self, directory, **overrides):
        script = Path(__file__).resolve().parents[1] / "seed_sim_clipboard.sh"
        source = script.read_text().split("/usr/bin/python3 - <<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith("TEST_RUNNER_COPAKY_")}
        environment.update(COPAKY_LANG="it", COPAKY_INCLUDE_YESTERDAY="0",
                           COPAKY_TABBAR=str(Path(directory) / "tabbar.json"),
                           COPAKY_HISTORY=str(Path(directory) / "history.json"),
                           TEST_RUNNER_COPAKY_H55_TOKEN=self.token)
        environment.update(overrides)
        return subprocess.run(["python3", "-c", source], env=environment,
                              capture_output=True, text=True, check=False)

    def test_three_unique_synthetic_entries_and_preserved_default_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_generator(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            entries = json.loads((Path(directory) / "history.json").read_text())
            self.assertEqual(len(entries), 3)
            self.assertEqual([entry["content"]["text"]["_0"] for entry in entries],
                             [f"COPAKY-H55-{self.token}-keep-pin",
                              f"COPAKY-H55-{self.token}-target-à-日本",
                              f"COPAKY-H55-{self.token}-keep-plain"])
            self.assertIn("pinnedDate", entries[0])
            self.assertNotIn("pinnedDate", entries[1])
            self.assertNotIn("pinnedDate", entries[2])
            result = self.run_generator(directory, TEST_RUNNER_COPAKY_H55_TOKEN="")
            self.assertEqual(result.returncode, 0, result.stderr)
            defaults = json.loads((Path(directory) / "history.json").read_text())
            self.assertEqual(len(defaults), 4)
            self.assertEqual(defaults[1]["content"]["text"]["_0"], "Il tuo codice di verifica è 482913")

    def test_invalid_token_fails_before_writing_history(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_generator(directory, TEST_RUNNER_COPAKY_H55_TOKEN="not-a-uuid")
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(directory) / "history.json").exists())

    def test_conflicting_fixture_fails_before_writing_history(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_generator(directory, COPAKY_INCLUDE_YESTERDAY="1")
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(directory) / "history.json").exists())

    def test_scripts_reject_invalid_qualification_inputs_before_external_commands(self):
        scripts_directory = Path(__file__).resolve().parents[1]
        scripts = {
            "seed_sim_clipboard.sh": [],
            "seed_sim_settings.sh": ["keyboard_type_en=roman"],
            "run_ui_test.sh": ["test68_simulatorSyntheticClipboardPinReopenSelectiveDelete"],
        }
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            # Any external call before rejection leaves a marker, including mkdir or simctl.
            blocked_bin = temporary / "bin"
            blocked_bin.mkdir()
            marker = temporary / "unexpected-command"
            for command in ["xcrun", "mkdir", "python3", "open", "sed", "dirname", "git"]:
                stub = blocked_bin / command
                stub.write_text('#!/bin/bash\nprintf "%s\\n" invoked >> "$H55_COMMAND_MARKER"\nexit 99\n')
                stub.chmod(0o700)
            base = {key: value for key, value in os.environ.items()
                    if not key.startswith(("TEST_RUNNER_COPAKY_", "COPAKY_"))}
            base.update(PATH=str(blocked_bin), H55_COMMAND_MARKER=str(marker),
                        COPAKY_UI_RESULTS_DIR=str(temporary / "uncreated-results"))
            cases = [
                {"TEST_RUNNER_COPAKY_H55_TOKEN": "invalid", "COPAKY_UDID": self.token},
                {"TEST_RUNNER_COPAKY_H55_TOKEN": self.token.upper(), "COPAKY_UDID": self.token},
                {"TEST_RUNNER_COPAKY_H55_TOKEN": self.token},
                {"TEST_RUNNER_COPAKY_H55_TOKEN": self.token, "COPAKY_UDID": "../../wrong-target"},
            ]
            for script, arguments in scripts.items():
                for overrides in cases:
                    with self.subTest(script=script, inputs=overrides):
                        result = subprocess.run(["/bin/bash", str(scripts_directory / script), *arguments],
                                                env=dict(base, **overrides), capture_output=True, text=True)
                        self.assertEqual(result.returncode, 2, result.stderr)
                        self.assertFalse(marker.exists(), "Validation must precede every external command")
                        self.assertFalse((temporary / "uncreated-results").exists())

    def test_three_scripts_never_signal_host_preference_daemons(self):
        scripts_directory = Path(__file__).resolve().parents[1]
        for name in ["seed_sim_clipboard.sh", "seed_sim_settings.sh", "run_ui_test.sh"]:
            source = (scripts_directory / name).read_text()
            self.assertNotRegex(source, r"(?:killall|pkill)[^\n]*cfprefsd", name)
            self.assertNotRegex(source, r"simctl\s+spawn[^\n]*killall", name)

    def test_postlaunch_readback_rejects_wrong_value_type_and_returned_delete(self):
        source = (Path(__file__).resolve().parents[1] / "run_ui_test.sh").read_text()
        generator = source[source.index("import plistlib, sys\narguments ="):].split("\nPY\n", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.plist"
            arguments = ["enabled=false", "enabled=true", "limit=3", "layout=roman", "--", "removed"]
            fixtures = [
                ({"enabled": True, "limit": 3, "layout": "roman"}, 0),
                ({"enabled": False, "limit": 3, "layout": "roman"}, 1),
                ({"enabled": 1, "limit": 3, "layout": "roman"}, 1),
                ({"enabled": True, "limit": "3", "layout": "roman"}, 1),
                ({"enabled": True, "limit": 3, "layout": "roman", "removed": False}, 1),
            ]
            for values, expected_code in fixtures:
                with self.subTest(values=values):
                    path.write_bytes(plistlib.dumps(values))
                    result = subprocess.run(["python3", "-c", generator, str(path), *arguments],
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, expected_code, result.stderr)


if __name__ == "__main__":
    unittest.main()
