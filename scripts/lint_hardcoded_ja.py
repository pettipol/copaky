#!/usr/bin/env python3
"""Advisory census of uncatalogued Japanese UI literals in keyboard Swift sources.

The scanner is deliberately narrow: it reports CJK-bearing Swift string literals used by
SwiftUI localization/UI entry points (Text, Button, Label, LocalizedStringKey, selected view
modifiers, and selected named arguments) only when the literal is absent from the String
Catalog. Legitimate Japanese input glyphs live in the companion allowlist.

Usage:  python3 scripts/lint_hardcoded_ja.py [--strict]

The default advisory mode always exits zero. --strict exits one when residuals remain.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "Resources" / "Localizable.xcstrings"
ALLOWLIST = REPO / "scripts" / "lint_hardcoded_ja_allowlist.txt"
SCAN_ROOTS = (
    REPO / "AzooKeyCore" / "Sources" / "KeyboardViews",
    REPO / "AzooKeyCore" / "Sources" / "KeyboardExtensionUtils",
    REPO / "AzooKeyCore" / "Sources" / "AzooKeyUtils",
    REPO / "Keyboard",
)

CALL_NAMES = (
    "Text",
    "Button",
    "Label",
    "LocalizedStringKey",
    "accessibilityLabel",
    "navigationTitle",
)
NAMED_ARGUMENTS = ("title", "explanation", "description", "placeholder", "prompt")
CALL_RE = re.compile(r"\b(?:" + "|".join(map(re.escape, CALL_NAMES)) + r")\s*\(")
NAMED_ARGUMENT_RE = re.compile(
    r"\b(?:" + "|".join(map(re.escape, NAMED_ARGUMENTS)) + r")\s*:"
)


@dataclass(frozen=True)
class SwiftLiteral:
    start: int
    end: int
    line: int
    value: str


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    literal: str


@dataclass(frozen=True)
class Census:
    candidates: int
    catalogued: int
    allowlisted: int
    findings: tuple[Finding, ...]


@dataclass(frozen=True)
class Allowlist:
    path_globs: tuple[str, ...]
    literals: tuple[tuple[str, str], ...]

    def contains(self, path: str, literal: str) -> bool:
        if any(fnmatch.fnmatchcase(path, pattern) for pattern in self.path_globs):
            return True
        return any(
            fnmatch.fnmatchcase(path, pattern) and literal == allowed
            for pattern, allowed in self.literals
        )


def _is_cjk(character: str) -> bool:
    codepoint = ord(character)
    return (
        0x3040 <= codepoint <= 0x309F
        or 0x30A0 <= codepoint <= 0x30FF
        or 0x4E00 <= codepoint <= 0x9FFF
        or 0x3000 <= codepoint <= 0x303F
        or 0xFF00 <= codepoint <= 0xFFEF
    )


def _has_cjk(value: str) -> bool:
    return any(_is_cjk(character) for character in value)


def _string_opener(source: str, start: int) -> tuple[int, bool] | None:
    """Return (raw-hash count, is-multiline) for a Swift string opener."""
    index = start
    while index < len(source) and source[index] == "#":
        index += 1
    if index >= len(source) or source[index] != '"':
        return None
    multiline = source.startswith('"""', index)
    return index - start, multiline


def _skip_block_comment(source: str, start: int) -> int:
    """Skip a Swift block comment, including Swift's supported nested comments."""
    depth = 1
    index = start + 2
    while index < len(source) and depth:
        if source.startswith("/*", index):
            depth += 1
            index += 2
        elif source.startswith("*/", index):
            depth -= 1
            index += 2
        else:
            index += 1
    return index


def _skip_line_comment(source: str, start: int) -> int:
    newline = source.find("\n", start + 2)
    return len(source) if newline == -1 else newline


def _skip_interpolation(source: str, start: int) -> int:
    """Return the index after an interpolation's matching closing parenthesis."""
    depth = 1
    index = start
    while index < len(source):
        if source.startswith("//", index):
            index = _skip_line_comment(source, index)
            continue
        if source.startswith("/*", index):
            index = _skip_block_comment(source, index)
            continue
        opener = _string_opener(source, index)
        if opener is not None:
            parsed = _parse_swift_string(source, index)
            index = parsed.end if parsed is not None else index + 1
            continue
        if source[index] == "(":
            depth += 1
        elif source[index] == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return index


def _decode_escape(source: str, index: int, marker: str) -> tuple[str, int]:
    """Decode one Swift escape beginning just after the marker."""
    if index >= len(source):
        return marker, index
    escaped = source[index]
    simple = {
        "0": "\0",
        "n": "\n",
        "r": "\r",
        "t": "\t",
        '"': '"',
        "'": "'",
        "\\": "\\",
    }
    if escaped in simple:
        return simple[escaped], index + 1
    if escaped == "u" and index + 1 < len(source) and source[index + 1] == "{":
        closing = source.find("}", index + 2)
        if closing != -1:
            digits = source[index + 2 : closing].replace("_", "")
            try:
                return chr(int(digits, 16)), closing + 1
            except (ValueError, OverflowError):
                pass
    if escaped == "\n":
        index += 1
        while index < len(source) and source[index] in " \t":
            index += 1
        return "", index
    return escaped, index + 1


def _parse_swift_string(source: str, start: int) -> SwiftLiteral | None:
    opener = _string_opener(source, start)
    if opener is None:
        return None
    hash_count, multiline = opener
    hashes = "#" * hash_count
    quote_index = start + hash_count
    quote = '"""' if multiline else '"'
    closing = quote + hashes
    marker = "\\" + hashes
    index = quote_index + len(quote)
    pieces: list[str] = []

    while index < len(source):
        if source.startswith(closing, index):
            end = index + len(closing)
            return SwiftLiteral(
                start=start,
                end=end,
                line=source.count("\n", 0, start) + 1,
                value="".join(pieces),
            )
        if source.startswith(marker + "(", index):
            index = _skip_interpolation(source, index + len(marker) + 1)
            # SwiftUI's LocalizedStringKey uses %@ for Image/String interpolation. The
            # normalized form lets an interpolated source literal match its catalog key.
            pieces.append("%@")
            continue
        if source.startswith(marker, index):
            decoded, index = _decode_escape(source, index + len(marker), marker)
            pieces.append(decoded)
            continue
        pieces.append(source[index])
        index += 1
    return SwiftLiteral(
        start=start,
        end=index,
        line=source.count("\n", 0, start) + 1,
        value="".join(pieces),
    )


def _mask_and_literals(source: str) -> tuple[str, list[SwiftLiteral]]:
    """Mask comments/strings while retaining offsets, and collect Swift literals."""
    mask = list(source)
    literals: list[SwiftLiteral] = []
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            end = _skip_line_comment(source, index)
        elif source.startswith("/*", index):
            end = _skip_block_comment(source, index)
        else:
            literal = _parse_swift_string(source, index)
            if literal is None:
                index += 1
                continue
            literals.append(literal)
            end = literal.end
        for masked_index in range(index, end):
            if mask[masked_index] != "\n":
                mask[masked_index] = " "
        index = end
    return "".join(mask), literals


def _parenthesis_pairs(mask: str) -> dict[int, int]:
    stack: list[int] = []
    pairs: dict[int, int] = {}
    for index, character in enumerate(mask):
        if character == "(":
            stack.append(index)
        elif character == ")" and stack:
            pairs[stack.pop()] = index
    return pairs


def _named_argument_end(mask: str, start: int, enclosing_close: int) -> int:
    parens = brackets = braces = 0
    index = start
    while index < enclosing_close:
        character = mask[index]
        if character == "(":
            parens += 1
        elif character == ")":
            if parens == 0:
                break
            parens -= 1
        elif character == "[":
            brackets += 1
        elif character == "]":
            brackets = max(0, brackets - 1)
        elif character == "{":
            braces += 1
        elif character == "}":
            braces = max(0, braces - 1)
        elif character == "," and parens == brackets == braces == 0:
            break
        index += 1
    return index


def _ui_ranges(mask: str) -> list[tuple[int, int]]:
    pairs = _parenthesis_pairs(mask)
    ranges: list[tuple[int, int]] = []

    for match in CALL_RE.finditer(mask):
        opening = mask.find("(", match.start(), match.end())
        if opening in pairs:
            ranges.append((opening + 1, pairs[opening]))

    for match in NAMED_ARGUMENT_RE.finditer(mask):
        colon = mask.find(":", match.start(), match.end())
        enclosing = [
            (opening, closing)
            for opening, closing in pairs.items()
            if opening < colon < closing
        ]
        if not enclosing:
            continue
        _, enclosing_close = max(enclosing, key=lambda pair: pair[0])
        value_start = colon + 1
        ranges.append(
            (value_start, _named_argument_end(mask, value_start, enclosing_close))
        )

    return ranges


def _decode_allowlist_literal(value: str) -> str:
    pieces: list[str] = []
    index = 0
    while index < len(value):
        if value[index] != "\\" or index + 1 >= len(value):
            pieces.append(value[index])
            index += 1
            continue
        decoded, index = _decode_escape(value, index + 1, "\\")
        pieces.append(decoded)
    return "".join(pieces)


def load_allowlist(path: Path) -> Allowlist:
    path_globs: list[str] = []
    literals: list[tuple[str, str]] = []
    if not path.exists():
        return Allowlist((), ())
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        path_pattern, separator, literal = line.partition(":")
        if separator:
            literals.append((path_pattern, _decode_allowlist_literal(literal)))
        else:
            path_globs.append(line)
    return Allowlist(tuple(path_globs), tuple(literals))


def load_catalog_keys(path: Path) -> set[str]:
    catalog = json.loads(path.read_text(encoding="utf-8"))
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        raise ValueError(f"{path}: missing object 'strings'")
    return set(strings)


def scan_file(path: Path, catalog_keys: set[str], allowlist: Allowlist) -> Census:
    source = path.read_text(encoding="utf-8")
    mask, literals = _mask_and_literals(source)
    ranges = _ui_ranges(mask)
    relative = path.relative_to(REPO).as_posix()
    candidates = catalogued = allowlisted = 0
    findings: list[Finding] = []
    for literal in literals:
        if not _has_cjk(literal.value):
            continue
        if not any(start <= literal.start < end for start, end in ranges):
            continue
        candidates += 1
        if literal.value in catalog_keys:
            catalogued += 1
            continue
        if allowlist.contains(relative, literal.value):
            allowlisted += 1
            continue
        findings.append(Finding(relative, literal.line, literal.value))
    return Census(candidates, catalogued, allowlisted, tuple(findings))


def scan(catalog_keys: set[str], allowlist: Allowlist) -> Census:
    paths = sorted(
        path
        for root in SCAN_ROOTS
        if root.exists()
        for path in root.rglob("*.swift")
        if path.is_file()
    )
    candidates = catalogued = allowlisted = 0
    findings: list[Finding] = []
    for path in paths:
        result = scan_file(path, catalog_keys, allowlist)
        candidates += result.candidates
        catalogued += result.catalogued
        allowlisted += result.allowlisted
        findings.extend(result.findings)
    ordered = tuple(
        sorted(findings, key=lambda finding: (finding.path, finding.line, finding.literal))
    )
    return Census(candidates, catalogued, allowlisted, ordered)


def _shown(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="exit 1 when uncatalogued, non-allowlisted UI literals remain",
    )
    return parser.parse_args(argv[1:])


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        catalog_keys = load_catalog_keys(CATALOG)
        allowlist = load_allowlist(ALLOWLIST)
        census = scan(catalog_keys, allowlist)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"✘ Hard-coded Japanese UI lint: scanner error: {error}")
        return 2 if args.strict else 0

    print(
        "Hard-coded Japanese UI candidates: "
        f"{census.candidates} "
        f"(catalogued: {census.catalogued}, allowlisted: {census.allowlisted})"
    )
    print(f"Hard-coded Japanese UI residuals: {len(census.findings)}")
    for finding in census.findings:
        print(f"{finding.path}:{finding.line}: {_shown(finding.literal)}")
    if not census.findings:
        print("✓ Hard-coded Japanese UI lint: no uncatalogued UI literals")
    return 1 if args.strict and census.findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
