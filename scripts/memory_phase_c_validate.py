#!/usr/bin/env python3
"""Copaky: validate phase-C evidence without running Xcode or contacting a device.

Exit 0: qualified device/Release run within 40,000,000 bytes; 1: over budget;
2: incomplete/invalid measurement (including simulator-only observations).
Monitor JSONL schema: pid/name/physFootprint/timestamp, observed in the 2026-08-29
run. Identity snapshots use sysmon process single's list with execName, checked
against pymobiledevice3's local implementation; never infer identity from name.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import plistlib
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

PHASES = [f"jp-{i}" for i in range(12)] + ["clipboard", "it"] + [f"jp-final-{i}" for i in range(3)]
EXECUTABLE_SUFFIX = "/azooKey.app/PlugIns/Keyboard.appex/Keyboard"
BUDGET_BYTES = 40_000_000  # Decimal MB, deliberately distinct from MiB and the 50 MB design constraint.
MIN_DURATION_SECONDS = 2.0
MAX_SAMPLE_GAP_SECONDS = 3.0
TEST_NAME = "test42_memoryPhaseC_japaneseTypingAcrossKana"


@dataclass(frozen=True)
class Sample:
    timestamp: datetime
    pid: int
    byte_count: int


def timestamp(value: str) -> datetime:
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("timestamp has no timezone")
    return result


def positive_int(value: Any) -> int:
    if isinstance(value, bool) or not re.fullmatch(r"[0-9]+", str(value)) or int(value) <= 0:
        raise ValueError("expected positive integer")
    return int(value)


def identities(path: Path) -> list[dict[str, Any]]:
    """Return only the exact extension path, rejecting malformed snapshot schemas."""
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise ValueError("sysmon single must be an array")
    if any(not isinstance(row, dict) or not {"pid", "execName"} <= row.keys() for row in data):
        raise ValueError("sysmon single identity fields missing")
    return [row for row in data if str(row["execName"]).endswith(EXECUTABLE_SUFFIX)]


def same_device(path: Path, device_id: str, lockdown_udid: str) -> bool:
    """Match CoreDevice and lockdown IDs using devicectl's existing runner schema."""
    devices = json.loads(path.read_text())["result"]["devices"]
    matches = [d for d in devices if d.get("identifier") == device_id or
               d.get("hardwareProperties", {}).get("udid") == device_id]
    return len(matches) == 1 and matches[0].get("hardwareProperties", {}).get("udid") == lockdown_udid


def load_samples(raw_dir: Path | None, csv_path: Path) -> tuple[list[Sample], list[str]]:
    samples: list[Sample] = []
    errors: list[str] = []
    records: list[dict[str, Any]] = []
    if raw_dir is not None:
        paths = sorted(raw_dir.glob("attach_*.jsonl"))
        if not paths:
            errors.append("no_monitor_files")
        for path in paths:
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                    if not isinstance(row, dict) or row.get("name") != "Keyboard":
                        raise ValueError("unexpected process record")
                    records.append({"timestamp": row["timestamp"], "pid": row["pid"],
                                    "physFootprint_bytes": row["physFootprint"]})
                except (ValueError, KeyError, TypeError):
                    errors.append(f"malformed_monitor_record:{path.name}:{number}")
    else:
        with csv_path.open(newline="") as source:
            records = list(csv.DictReader(source))
    for index, row in enumerate(records, 1):
        try:
            samples.append(Sample(timestamp(row["timestamp"]), positive_int(row["pid"]),
                                  positive_int(row["physFootprint_bytes"])))
        except (ValueError, KeyError, TypeError):
            errors.append(f"malformed_sample:{index}")
    samples.sort(key=lambda sample: sample.timestamp)
    if len({(sample.timestamp, sample.pid) for sample in samples}) != len(samples):
        errors.append("duplicate_samples")
    if raw_dir is not None:
        with csv_path.open("w", newline="") as output:
            writer = csv.writer(output)
            writer.writerow(["timestamp", "pid", "physFootprint_bytes"])
            writer.writerows((s.timestamp.isoformat(), s.pid, s.byte_count) for s in samples)
    return samples, errors


def artifact_metadata(app_path: Path) -> dict[str, Any]:
    extension = app_path / "PlugIns/Keyboard.appex"
    result: dict[str, Any] = {}
    for role, folder in (("app", app_path), ("extension", extension)):
        with (folder / "Info.plist").open("rb") as source:
            info = plistlib.load(source)
        binary = folder / info["CFBundleExecutable"]
        result[role] = {"bundle_id": info["CFBundleIdentifier"], "build": info["CFBundleVersion"],
                        "version": info["CFBundleShortVersionString"],
                        "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
    return result


def validate(log_text: str, samples: list[Sample], provenance: dict[str, Any],
             process_records: list[dict[str, Any]], prior_pids: list[int],
             initial_errors: list[str] | None = None) -> dict[str, Any]:
    errors = list(initial_errors or [])
    markers: dict[str, dict[str, datetime]] = {}
    outcomes: dict[str, str] = {}
    for line in log_text.splitlines():
        line = line.strip()
        if line.startswith("MEMC|"):
            try:
                _, phase, edge, value = line.split("|", 3)
                if phase not in PHASES + ["begin", "end"] or edge not in ("start", "end"):
                    raise ValueError("unexpected marker")
                if edge in markers.setdefault(phase, {}):
                    raise ValueError("duplicate marker")
                markers[phase][edge] = timestamp(value)
            except (ValueError, TypeError):
                errors.append(f"invalid_marker:{line}")
        elif line.startswith("MEMC-RESULT|"):
            try:
                _, phase, outcome, reason = line.split("|", 3)
                if phase not in PHASES or phase in outcomes or not reason:
                    raise ValueError("unexpected or duplicate result")
                outcomes[phase] = outcome
            except ValueError:
                errors.append(f"invalid_result:{line}")
    if provenance.get("mode") != "device" or provenance.get("configuration") != "Release":
        errors.append("requires_device_release")
    if provenance.get("xcodebuild_status") != 0 or provenance.get("sampler_died") != 0:
        errors.append("test_or_sampler_failed")
    if provenance.get("device_mapping_verified") is not True:
        errors.append("sampler_test_device_mapping_unproved")
    if not re.search(r"Test Case .*" + TEST_NAME + r".* passed \(", log_text) or "** TEST SUCCEEDED **" not in log_text:
        errors.append("test42_success_not_observed")
    if re.search(r"Test Case .*" + TEST_NAME + r".* (failed|skipped) \(", log_text):
        errors.append("test42_failed_or_skipped")
    if not provenance.get("artifact", {}).get("extension", {}).get("binary_sha256"):
        errors.append("built_artifact_identity_missing")
    begin, finish = markers.get("begin", {}).get("start"), markers.get("end", {}).get("end")
    if begin is None or finish is None or finish <= begin:
        errors.append("campaign_boundaries_missing_or_invalid")
    phase_results: list[dict[str, Any]] = []
    previous_end = begin
    for phase in PHASES:
        start, end = markers.get(phase, {}).get("start"), markers.get(phase, {}).get("end")
        row: dict[str, Any] = {"phase": phase, "outcome": outcomes.get(phase, "MISSING")}
        if outcomes.get(phase) != "PASS":
            errors.append(f"phase_not_pass:{phase}")
        if start is None or end is None:
            errors.append(f"phase_edges_missing:{phase}")
        else:
            row["duration_seconds"] = (end - start).total_seconds()
            if row["duration_seconds"] < MIN_DURATION_SECONDS:
                errors.append(f"phase_too_short:{phase}")
            if previous_end is not None and start < previous_end or finish is not None and end > finish:
                errors.append(f"phase_out_of_order:{phase}")
            previous_end = end
            window = [s for s in samples if start <= s.timestamp <= end]
            row["samples"] = len(window)
            if len(window) < 2:
                errors.append(f"phase_samples_missing:{phase}")
            elif end > start:
                times = [start] + [s.timestamp for s in window] + [end]
                if max((b - a).total_seconds() for a, b in zip(times, times[1:])) > MAX_SAMPLE_GAP_SECONDS:
                    errors.append(f"phase_sample_gap:{phase}")
            row["peak_bytes"] = max((s.byte_count for s in window), default=None)
        phase_results.append(row)
    campaign_samples = [s for s in samples if begin is not None and finish is not None and begin <= s.timestamp <= finish]
    pids = sorted({s.pid for s in campaign_samples})
    if len(pids) != 1:
        errors.append("campaign_pid_missing_or_changed")
    if set(pids) & set(prior_pids):
        errors.append("process_not_fresh")
    for pid in pids:
        matching = [r for r in process_records if r.get("pid") == pid and
                    str(r.get("execName", "")).endswith(EXECUTABLE_SUFFIX)]
        if not matching:
            errors.append(f"process_identity_unproved:{pid}")
    if campaign_samples:
        times = [begin] + [s.timestamp for s in campaign_samples] + [finish]
        if max((b - a).total_seconds() for a, b in zip(times, times[1:])) > MAX_SAMPLE_GAP_SECONDS:
            errors.append("campaign_sample_gap")
    campaign_peak = max((s.byte_count for s in campaign_samples), default=None)
    # Copaky: startup/teardown samples of the qualified process also consume the memory budget.
    # An old or unrelated PID outside the workload must not be attributed to this process.
    qualified_samples = [s for s in samples if len(pids) == 1 and s.pid == pids[0]]
    peak = max((s.byte_count for s in qualified_samples), default=None)
    observed_peak = max((s.byte_count for s in samples), default=None)
    budget_status = "NOT_QUALIFIED" if errors else "OVER_BUDGET" if peak is not None and peak > BUDGET_BYTES else "WITHIN_BUDGET"
    status = "MEASUREMENT_ERROR" if errors else "OVER_BUDGET" if budget_status == "OVER_BUDGET" else "PASS"
    return {"schema_version": 1, "status": status, "measurement_status": "INVALID" if errors else "COMPLETE",
            "budget_status": budget_status, "budget_bytes": BUDGET_BYTES, "budget_decimal_MB": 40,
            "peak_bytes": peak, "peak_MiB": peak / 2**20 if peak is not None else None,
            "peak_scope": "all_recorded_samples_of_qualified_pid", "campaign_peak_bytes": campaign_peak,
            "all_samples_peak_bytes": observed_peak, "sample_count": len(samples),
            "campaign_sample_count": len(campaign_samples), "process_pids": pids,
            "errors": sorted(set(errors)), "phases": phase_results, "provenance": provenance,
            "limits": ["Sampled physFootprint, not a universal jetsam threshold.",
                       "Binary hash identifies local build output; no remote installed-binary hash attestation."]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--select-pids", type=Path, help="read sysmon single JSON; no device access")
    parser.add_argument("--device-map", type=Path)
    parser.add_argument("--device-id")
    parser.add_argument("--device-udid")
    parser.add_argument("--log", type=Path)
    parser.add_argument("--csv", type=Path)
    parser.add_argument("--raw-dir", type=Path)
    parser.add_argument("--provenance", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    if args.device_map:
        try:
            return 0 if same_device(args.device_map, args.device_id, args.device_udid) else 2
        except (OSError, ValueError, KeyError, TypeError):
            return 2
    if args.select_pids:
        try:
            print("\n".join(str(positive_int(row["pid"])) for row in identities(args.select_pids)))
            return 0
        except (OSError, ValueError, KeyError):
            return 2
    if not all((args.log, args.csv, args.json)):
        parser.error("--log, --csv and --json are required")
    errors: list[str] = []
    provenance: dict[str, Any] = {}
    process_records: list[dict[str, Any]] = []
    prior_pids: list[int] = []
    samples: list[Sample] = []
    log_text = ""
    try:
        log_text = args.log.read_text(errors="replace")
        samples, load_errors = load_samples(args.raw_dir, args.csv)
        errors.extend(load_errors)
        if args.provenance:
            provenance = json.loads(args.provenance.read_text())
        if args.app:
            provenance["artifact"] = artifact_metadata(args.app)
        if args.raw_dir:
            prior_pids = [positive_int(row["pid"]) for row in identities(args.raw_dir / "before.json")]
            paths = sorted(args.raw_dir.glob("identity_*.json"))
            if not paths:
                errors.append("process_identity_snapshots_missing")
            for path in paths:
                if path.stat().st_size:
                    process_records.extend(identities(path))
        else:
            errors.append("process_freshness_unproved")
    except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException) as exc:
        errors.append(f"evidence_read_error:{type(exc).__name__}")
    provenance["log_sha256"] = hashlib.sha256(log_text.encode()).hexdigest()
    if args.csv.exists():
        provenance["csv_sha256"] = hashlib.sha256(args.csv.read_bytes()).hexdigest()
    report = validate(log_text, samples, provenance, process_records, prior_pids, errors)
    args.json.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"{report['status']}: peak={report['peak_bytes']} bytes; gate={BUDGET_BYTES} bytes (40 MB decimal)")
    for error in report["errors"]:
        print(f"  {error}")
    return {"PASS": 0, "OVER_BUDGET": 1, "MEASUREMENT_ERROR": 2}[report["status"]]


if __name__ == "__main__":
    sys.exit(main())
