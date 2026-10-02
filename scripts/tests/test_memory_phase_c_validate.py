"""Copaky: synthetic evidence mutations, no Xcode/simulator/device access."""
from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from memory_phase_c_validate import (  # noqa: E402
    BUDGET_BYTES, EXECUTABLE_SUFFIX, PHASES, Sample, identities, load_samples, same_device, validate,
)


class MemoryPhaseValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.start = datetime(2026, 1, 1, tzinfo=timezone.utc)
        self.lines = [f"MEMC|begin|start|{self.start.isoformat()}"]
        for i, phase in enumerate(PHASES):
            start = self.start + timedelta(seconds=4 * i)
            end = start + timedelta(seconds=4)
            self.lines.extend([f"MEMC|{phase}|start|{start.isoformat()}",
                               f"MEMC|{phase}|end|{end.isoformat()}",
                               f"MEMC-RESULT|{phase}|PASS|workload-observed"])
        self.lines.extend([f"MEMC|end|end|{(self.start + timedelta(seconds=68)).isoformat()}",
                           "Test Case '-[azooKeyUITests.CopakyCampaignTests test42_memoryPhaseC_japaneseTypingAcrossKana]' passed (68 seconds).",
                           "** TEST SUCCEEDED **"])
        self.samples = [Sample(self.start + timedelta(seconds=i), 42, 20_000_000) for i in range(69)]
        self.provenance = {"mode": "device", "configuration": "Release", "xcodebuild_status": 0,
                           "device_mapping_verified": True,
                           "sampler_died": 0, "artifact": {"extension": {"binary_sha256": "synthetic"}}}
        self.identity = [{"pid": 42, "execName": "/synthetic" + EXECUTABLE_SUFFIX}]

    def report(self, **kwargs):
        return validate("\n".join(kwargs.pop("lines", self.lines)), kwargs.pop("samples", self.samples),
                        kwargs.pop("provenance", self.provenance), kwargs.pop("process_records", self.identity),
                        kwargs.pop("prior_pids", [41]), **kwargs)

    def assert_invalid(self, report, error: str) -> None:
        self.assertEqual(report["status"], "MEASUREMENT_ERROR", "incomplete measurements must never pass")
        self.assertEqual(report["budget_status"], "NOT_QUALIFIED")
        self.assertIn(error, report["errors"])

    def test_complete_run_and_decimal_budget_boundary(self):
        samples = [Sample(s.timestamp, s.pid, BUDGET_BYTES) for s in self.samples]
        self.assertEqual(self.report(samples=samples)["status"], "PASS")
        samples[10] = Sample(samples[10].timestamp, 42, BUDGET_BYTES + 1)
        report = self.report(samples=samples)
        self.assertEqual(report["status"], "OVER_BUDGET")
        self.assertEqual(report["measurement_status"], "COMPLETE")
        self.assertEqual(report["peak_bytes"], 40_000_001)
        self.assertAlmostEqual(report["peak_MiB"], 40_000_001 / 2**20)

    def test_skipped_phase_cannot_count_as_work(self):
        for phase in ("clipboard", "it"):
            with self.subTest(phase=phase):
                lines = [line.replace(f"|{phase}|", f"|{phase}-skipped|") for line in self.lines]
                self.assert_invalid(self.report(lines=lines), f"phase_not_pass:{phase}")

    def test_same_pid_startup_and_teardown_peaks_count_towards_budget(self):
        for seconds in (-5, 75):
            with self.subTest(seconds=seconds):
                samples = self.samples + [Sample(self.start + timedelta(seconds=seconds), 42, 50_000_000)]
                report = self.report(samples=sorted(samples, key=lambda s: s.timestamp))
                self.assertEqual(report["status"], "OVER_BUDGET")
                self.assertEqual(report["peak_bytes"], 50_000_000)
                self.assertEqual(report["campaign_peak_bytes"], 20_000_000)

    def test_other_pid_outside_campaign_is_not_attributed(self):
        samples = [Sample(self.start - timedelta(seconds=5), 41, 50_000_000)] + self.samples
        report = self.report(samples=samples)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["peak_bytes"], 20_000_000)
        self.assertEqual(report["all_samples_peak_bytes"], 50_000_000)

    def test_zero_duration_final_japanese_phase_rejected(self):
        lines = list(self.lines)
        i = lines.index(next(line for line in lines if line.startswith("MEMC|jp-final-2|end|")))
        lines[i] = lines[i - 1].replace("|start|", "|end|")
        self.assert_invalid(self.report(lines=lines), "phase_too_short:jp-final-2")

    def test_missing_result_or_edge_rejected(self):
        for prefix, error in (("MEMC-RESULT|clipboard|", "phase_not_pass:clipboard"),
                              ("MEMC|it|end|", "phase_edges_missing:it")):
            self.assert_invalid(self.report(lines=[l for l in self.lines if not l.startswith(prefix)]), error)

    def test_failed_workload_rejected_despite_xctest_success(self):
        lines = [line.replace("MEMC-RESULT|it|PASS|", "MEMC-RESULT|it|FAIL|") for line in self.lines]
        self.assert_invalid(self.report(lines=lines), "phase_not_pass:it")

    def test_unsampled_phase_and_long_sampling_gap_rejected(self):
        samples = [s for s in self.samples if not 47 <= (s.timestamp - self.start).total_seconds() <= 53]
        self.assert_invalid(self.report(samples=samples), "phase_samples_missing:clipboard")
        samples = [s for s in self.samples if not 9 <= (s.timestamp - self.start).total_seconds() <= 11]
        self.assert_invalid(self.report(samples=samples), "phase_sample_gap:jp-2")

    def test_pid_switch_stale_pid_and_unrelated_keyboard_rejected(self):
        samples = list(self.samples)
        samples[30] = Sample(samples[30].timestamp, 43, 20_000_000)
        self.assert_invalid(self.report(samples=samples), "campaign_pid_missing_or_changed")
        self.assert_invalid(self.report(prior_pids=[42]), "process_not_fresh")
        self.assert_invalid(self.report(process_records=[{"pid": 42, "execName": "/other/Keyboard"}]),
                            "process_identity_unproved:42")

    def test_simulator_debug_and_missing_artifact_not_qualified(self):
        for key, value, error in (("mode", "sim", "requires_device_release"),
                                  ("configuration", "Debug", "requires_device_release"),
                                  ("artifact", {}, "built_artifact_identity_missing"),
                                  ("device_mapping_verified", False, "sampler_test_device_mapping_unproved"),
                                  ("sampler_died", 1, "test_or_sampler_failed")):
            provenance = copy.deepcopy(self.provenance)
            provenance[key] = value
            self.assert_invalid(self.report(provenance=provenance), error)

    def test_xctest_skip_not_qualified(self):
        lines = [line.replace("' passed (", "' skipped (") for line in self.lines]
        self.assert_invalid(self.report(lines=lines), "test42_success_not_observed")

    def test_duplicate_marker_and_wrong_order_rejected(self):
        self.assert_invalid(self.report(lines=self.lines + [self.lines[1]]),
                            "invalid_marker:" + self.lines[1])
        lines = [l.replace("MEMC|it|start|", "MEMC|it|start|") for l in self.lines]
        i = next(i for i, line in enumerate(lines) if line.startswith("MEMC|it|start|"))
        lines[i] = "MEMC|it|start|" + self.start.isoformat()
        self.assert_invalid(self.report(lines=lines), "phase_out_of_order:it")

    def test_raw_schema_and_malformed_record_are_not_silently_discarded(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            # Same field names/types as the 29-August monitor; synthetic PID/time/value.
            row = {"pid": 42, "name": "Keyboard", "physFootprint": 20_000_000,
                   "timestamp": self.start.isoformat()}
            monitor = root / "attach_001.jsonl"
            monitor.write_text(json.dumps(row) + "\n")
            samples, errors = load_samples(root, root / "samples.csv")
            self.assertEqual(len(samples), 1)
            self.assertEqual(errors, [])
            monitor.write_text(json.dumps(row) + "\n{broken\n")
            _, errors = load_samples(root, root / "samples.csv")
            self.assertIn("malformed_monitor_record:attach_001.jsonl:2", errors)
            row["physFootprint"] = "20MB"
            monitor.write_text(json.dumps(row) + "\n")
            _, errors = load_samples(root, root / "samples.csv")
            self.assertEqual(errors, ["malformed_sample:1"])

    def test_identity_snapshot_requires_exact_extension_path(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "single.json"
            path.write_text(json.dumps(self.identity + [{"pid": 9, "execName": "/other/Keyboard"}]))
            self.assertEqual([r["pid"] for r in identities(path)], [42])
            path.write_text('{"pid":42}')
            with self.assertRaises(ValueError):
                identities(path)

    def test_different_sampling_and_test_devices_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "devices.json"
            path.write_text(json.dumps({"result": {"devices": [
                {"identifier": "synthetic-core", "hardwareProperties": {"udid": "synthetic-usb"}}
            ]}}))
            self.assertTrue(same_device(path, "synthetic-core", "synthetic-usb"))
            self.assertFalse(same_device(path, "synthetic-core", "another-phone"))


if __name__ == "__main__":
    unittest.main()
