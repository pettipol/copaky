"""Copaky: synthetic runner results; no simulator required."""
import sys
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ui_result_validate import validate


class UIResultValidationTests(unittest.TestCase):
    def setUp(self):
        self.summary = {"totalTestCount": 1, "passedTests": 1, "failedTests": 0,
                        "skippedTests": 0, "result": "Passed"}

    def test_one_pass(self):
        self.assertEqual(validate(self.summary, 0)["status"], "PASS")

    def test_zero_tests(self):
        self.summary.update(totalTestCount=0, passedTests=0)
        self.assertEqual(validate(self.summary, 0)["status"], "ERROR")

    def test_skipped_is_not_pass(self):
        self.summary.update(passedTests=0, skippedTests=1, result="Skipped")
        self.assertEqual(validate(self.summary, 0)["status"], "SKIP")

    def test_failed_is_not_pass(self):
        self.summary.update(passedTests=0, failedTests=1, result="Failed")
        self.assertEqual(validate(self.summary, 65)["status"], "FAIL")

    def test_process_failure_despite_green_counts(self):
        self.assertEqual(validate(self.summary, 65)["status"], "FAIL")

    def test_malformed_counts(self):
        for value in (-1, "1", True, None):
            with self.subTest(value=value):
                self.assertEqual(validate(dict(self.summary, passedTests=value), 0)["status"], "ERROR")

    def test_wrong_count_or_inconsistent_totals(self):
        for change in ({"totalTestCount": 2, "passedTests": 2}, {"skippedTests": 1},
                       {"result": "Failed"}):
            self.assertEqual(validate(dict(self.summary, **change), 0)["status"], "ERROR")

    def test_missing_or_non_object(self):
        for value in ({}, [], None):
            self.assertEqual(validate(value, 0)["status"], "ERROR")

    def test_identity_must_match_selected_case(self):
        selected = "azooKeyUITests/CopakyBenchmarkTests/test62_realTypingScenarios"
        case = {"nodeType": "Test Case", "nodeIdentifierURL": "test://project/" + selected,
                "result": "Passed"}
        tree = {"testNodes": [{"children": [case]}]}
        self.assertEqual(validate(self.summary, 0, test_tree=tree, test_id=selected)["status"], "PASS")
        for wrong in (None, {"testNodes": []}, {"testNodes": [case, case]}):
            self.assertEqual(validate(self.summary, 0, test_tree=wrong, test_id=selected)["status"], "ERROR")
        self.assertEqual(validate(self.summary, 0, test_tree=tree, test_id=selected + "Wrong")["status"], "ERROR")
        case["result"] = "Skipped"
        self.assertEqual(validate(self.summary, 0, test_tree=tree, test_id=selected)["status"], "ERROR")

    def test_cli_skip_exit_code_and_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "summary.json").write_text(json.dumps(dict(self.summary, passedTests=0,
                                                              skippedTests=1, result="Skipped")))
            (root / "tests.json").write_text(json.dumps({"testNodes": [
                {"nodeType": "Test Case", "nodeIdentifierURL": "test://project/bundle/class/method", "result": "Skipped"}]}))
            process = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / "ui_result_validate.py"),
                                      str(root / "summary.json"), "--tests", str(root / "tests.json"),
                                      "--xcodebuild-status", "0", "--test-id", "bundle/class/method",
                                      "--result-bundle", "synthetic.xcresult", "--output", str(root / "receipt.json")],
                                     capture_output=True, text=True)
            self.assertEqual(process.returncode, 3, process.stderr)
            self.assertEqual(json.loads((root / "receipt.json").read_text())["status"], "SKIP")
