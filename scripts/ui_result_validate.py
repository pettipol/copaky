#!/usr/bin/env python3
"""Copaky: fail-closed result receipt for one explicitly selected simulator test."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


def validate(summary: Any, xcodebuild_status: int, *, test_tree: Any = None,
             test_id: str | None = None) -> dict[str, Any]:
    """Require one executed, passing test; report skip and infrastructure separately."""
    receipt: dict[str, Any] = {"status": "ERROR", "xcodebuild_status": xcodebuild_status}
    if test_id is not None:
        cases: list[dict[str, Any]] = []

        def collect(value: Any) -> None:
            if isinstance(value, dict):
                if value.get("nodeType") == "Test Case":
                    cases.append(value)
                for child in value.values():
                    collect(child)
            elif isinstance(value, list):
                for child in value:
                    collect(child)

        collect(test_tree)
        if len(cases) != 1 or not str(cases[0].get("nodeIdentifierURL", "")).removesuffix("()").endswith("/" + test_id):
            return dict(receipt, reason="executed_test_identity_not_proved")
        receipt["observed_test_url"] = cases[0]["nodeIdentifierURL"]
        if cases[0].get("result") != "Passed" and isinstance(summary, dict) and summary.get("passedTests") == 1:
            return dict(receipt, reason="test_tree_disagrees_with_summary")
    fields = ("totalTestCount", "passedTests", "failedTests", "skippedTests")
    if not isinstance(summary, dict) or any(
        type(summary.get(key)) is not int or summary[key] < 0 for key in fields
    ):
        return dict(receipt, reason="missing_or_invalid_counts")
    receipt["counts"] = {key: summary[key] for key in fields}
    total, passed, failed, skipped = (summary[key] for key in fields)
    if total != 1 or passed + failed + skipped != total:
        return dict(receipt, reason="expected_exactly_one_test_with_consistent_counts")
    if failed or xcodebuild_status:
        return dict(receipt, status="FAIL", reason="test_or_process_failed")
    if skipped:
        return dict(receipt, status="SKIP", reason="selected_test_skipped")
    if passed != 1 or summary.get("result") != "Passed" or summary.get("expectedFailures", 0) != 0:
        return dict(receipt, reason="summary_not_unconditionally_passed")
    return dict(receipt, status="PASS", reason="one_test_passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("--xcodebuild-status", type=int, required=True)
    parser.add_argument("--test-id", required=True)
    parser.add_argument("--tests", type=Path, required=True)
    parser.add_argument("--result-bundle", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = validate(json.loads(args.summary.read_text()), args.xcodebuild_status,
                          test_tree=json.loads(args.tests.read_text()), test_id=args.test_id)
    except (OSError, ValueError) as exc:
        result = {"status": "ERROR", "reason": f"summary_unreadable:{type(exc).__name__}",
                  "xcodebuild_status": args.xcodebuild_status}
    result.update(test_id=args.test_id, result_bundle=args.result_bundle,
                  summary_path=str(args.summary))
    provenance = args.output.parent / "provenance.json"
    if provenance.is_file():
        result.update(provenance_path=str(provenance),
                      provenance_sha256=hashlib.sha256(provenance.read_bytes()).hexdigest())
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return {"PASS": 0, "FAIL": 1, "ERROR": 2, "SKIP": 3}[result["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
