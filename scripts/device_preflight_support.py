#!/usr/bin/env python3
"""Static Xcode/iOS table helpers for the device preflight.

The table is a diagnostic reference only. It does not establish device, DDI,
or runtime compatibility.
"""

from __future__ import annotations

import re
import sys


_VERSION = re.compile(r"\d+(?:\.\d+){0,2}\Z")
_RANGES = {27: "17-27", 26: "15-26.5"}


def parse_version(value: str) -> tuple[int, ...] | None:
    """Parse one to three numeric components; reject malformed input."""
    if not _VERSION.fullmatch(value):
        return None
    return tuple(int(part) for part in value.split("."))


def xcode_ios_range(xcode_version: str) -> str | None:
    """Return the existing table row for an Xcode version's major, if any."""
    parsed = parse_version(xcode_version)
    if parsed is None:
        return None
    return _RANGES.get(parsed[0])


def classify_ios_version(ios_version: str, table_range: str | None) -> str:
    """Classify against the table without making a compatibility assertion."""
    ios = parse_version(ios_version)
    if ios is None:
        return "INVALID"
    if not table_range or table_range.count("-") != 1:
        return "NOT_DETERMINED"
    lower_text, upper_text = table_range.split("-", 1)
    lower = parse_version(lower_text)
    upper = parse_version(upper_text)
    if lower is None or upper is None:
        return "NOT_DETERMINED"

    # The table only names the maximum major, not its supported minor/patch
    # releases. Treat that entire major as unresolved, including the bare major.
    if ios[0] >= upper[0]:
        return "NOT_DETERMINED"

    padded_ios = ios + (0,) * (3 - len(ios))
    padded_lower = lower + (0,) * (3 - len(lower))
    if padded_ios < padded_lower:
        return "OUTSIDE_TABLE"
    return "IN_TABLE"


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[1] == "range":
        print(xcode_ios_range(argv[2]) or "")
        return 0
    if len(argv) == 4 and argv[1] == "classify":
        print(classify_ios_version(argv[2], argv[3] or None))
        return 0
    print("usage: device_preflight_support.py range XCODE_VERSION | classify IOS_VERSION TABLE_RANGE", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
