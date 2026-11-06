"""Copaky: exercise the runner's actual coverage gate with synthetic sysmon counters."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

RUNNER = Path(__file__).resolve().parents[1] / "memory_phase_c.sh"
COVERAGE = RUNNER.read_text().split("<<'PYCOVERAGE'\n", 1)[1].split("\nPYCOVERAGE\n", 1)[0]


class WorkloadCoverageTests(unittest.TestCase):
    def run_gate(self, offsets, *, pid_overrides=None, include_end=True):
        start = datetime(2026, 1, 1, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "run.log"
            end_marker = f"MEMC|end|end|{(start + timedelta(seconds=10)).isoformat()}\n" if include_end else ""
            log.write_text(f"MEMC|begin|start|{start.isoformat()}\n" + end_marker)
            rows = [{"name": "Keyboard", "pid": (pid_overrides or {}).get(offset, 42),
                     "timestamp": (start + timedelta(seconds=offset)).isoformat(),
                     "physFootprint": 20_000_000} for offset in offsets]
            (root / "attach_001.jsonl").write_text("\n".join(json.dumps(row) for row in rows))
            output = root / "coverage.json"
            result = subprocess.run([sys.executable, "-", str(root), str(log), str(output)],
                                    input=COVERAGE, text=True, capture_output=True,
                                    env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
            self.assertTrue(output.exists(), result.stderr)
            return result.returncode, json.loads(output.read_text())

    def test_real_record_counters_and_cold_start_limit(self):
        status, report = self.run_gate(range(-1, 12))
        self.assertEqual(status, 0)
        self.assertEqual(report["raw_records"], 13)
        self.assertEqual(report["valid_samples"], 13)
        self.assertEqual(report["workload_samples"], 11)
        self.assertEqual(report["before_workload"], 2)
        self.assertEqual(report["after_workload"], 2)
        self.assertEqual(report["cold_start"], "NOT_QUALIFIED")

    def test_missing_end_preserves_real_samples_without_inventing_coverage(self):
        status, report = self.run_gate(range(-1, 26), include_end=False)
        self.assertEqual(status, 2)
        self.assertEqual(report["raw_records"], 27)
        self.assertEqual(report["valid_samples"], 27)
        self.assertIsNone(report["workload_samples"], "No end marker means coverage cannot be computed")
        self.assertIsNone(report["after_workload"])
        self.assertIn("first_observed_sample", report)
        self.assertIn("last_observed_sample", report)
        self.assertEqual(report["status"], "INVALID")

    def test_late_attach_cannot_qualify_full_workload(self):
        status, report = self.run_gate(range(1, 12))
        self.assertEqual(status, 2)
        self.assertEqual(report["before_workload"], 0)
        self.assertEqual(report["status"], "INVALID")

    def test_early_detach_cannot_qualify_full_workload(self):
        status, report = self.run_gate(range(-1, 10))
        self.assertEqual(status, 2)
        self.assertEqual(report["after_workload"], 0)

    def test_distant_boundary_samples_rejected(self):
        for offsets in ([-4] + list(range(1, 12)), list(range(-1, 10)) + [14]):
            with self.subTest(offsets=offsets):
                status, report = self.run_gate(offsets)
                self.assertEqual(status, 2)
                self.assertIn("gap exceeds", report["error"])

    def test_other_process_cannot_supply_missing_boundary(self):
        status, report = self.run_gate(range(-1, 12), pid_overrides={-1: 41, 0: 41})
        self.assertEqual(status, 2)
        self.assertIn("changed workload PID", report["error"])

    def test_changed_process_during_workload_rejected(self):
        status, report = self.run_gate(range(-1, 12), pid_overrides={5: 43})
        self.assertEqual(status, 2)
        self.assertIn("changed workload PID", report["error"])


if __name__ == "__main__":
    unittest.main()
