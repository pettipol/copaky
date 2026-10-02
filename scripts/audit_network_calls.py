#!/usr/bin/env python3
"""Copaky: lexical offline gate for the reviewed local Keyboard source scope.

Exit 0 = static PASS, 1 = unapproved reference, 2 = incomplete/erroring scan.
This is not a call-graph analysis or proof of runtime network isolation.
静的検査のみ。実機の通信・外部依存コードの検証を意味しない。
"""

import os
import re
import sys
from pathlib import Path

# Reviewed against Keyboard's synchronized groups and packageProductDependencies
# in azooKey.xcodeproj/project.pbxproj. All five local package targets are linked
# by Keyboard; scan the entire Sources tree, including any newly added target.
# EmojiDictionary currently contains data only, but is also a synchronized group.
SOURCE_ROOTS = ("Keyboard", "AzooKeyCore/Sources", "azooKey_emoji_dictionary_storage/EmojiDictionary")
SHARED_TARGETS = ("AzooKeyUtils", "KeyboardExtensionUtils", "KeyboardThemes", "KeyboardViews", "SwiftUIUtils")
MANIFEST = "AzooKeyCore/Package.swift"
NATIVE_SUFFIXES = {".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".m", ".mm"}
PATTERNS = (
    ("URL_LOADING", re.compile(r"\b(?:URLSession\w*|NSURLSession\w*|URLRequest|NSURLRequest|NSURLConnection)\b")),
    ("NETWORK_FRAMEWORK", re.compile(r"\b(?:NWConnection\w*|NWListener|NWBrowser|nw_connection_\w+)\b")),
    ("SOCKET", re.compile(r"\b(?:Socket|CFSocket\w*|CFStreamCreatePairWithSocket\w*|CFReadStreamCreateForHTTPRequest)\b|\b(?:socket|connect|getaddrinfo)\s*\(")),
    ("NETWORK_IMPORT", re.compile(r"\bimport\s+(?:Network|NetworkExtension|CFNetwork|WebKit)\b")),
    ("WEB_VIEW", re.compile(r"\b(?:WKWebView|UIWebView|AsyncImage)\b")),
    ("HTTP_URL", re.compile(r"https?://", re.IGNORECASE)),
)

# Copaky: exact path + rule + complete source line; never exempt a directory, API,
# arbitrary URL, or runtime source. A pin change requires a fresh review here.
# These URLs locate build-time dependencies; their code is NOT covered by this gate.
ALLOWED_REFERENCES = {
    (MANIFEST, "HTTP_URL", '.package(url: "https://github.com/pettipol/AzooKeyKanaKanjiConverter", revision: "21e2bdcf59ec3cc91610bac6696b2e0c6402a296"),'):
        "Pinned converter repository locator in the build manifest; not a runtime request.",
    (MANIFEST, "HTTP_URL", '.package(url: "https://github.com/azooKey/CustardKit", revision: "7bddc14eb3f8f0145c6f3a4fea20cf394f8104e8"),'):
        "Pinned CustardKit repository locator in the build manifest; not a runtime request.",
}


def without_comments(source: str) -> str:
    """Mask nested Swift comments, preserving strings, code and line positions."""
    out = list(source)
    i = 0
    depth = 0
    # (string closing delimiter, interpolation parenthesis depth). Root code has
    # neither. Interpolations may contain nested strings, comments and closures.
    frames = [("", 0)]
    while i < len(source):
        delimiter, parentheses = frames[-1]
        if depth:
            if source.startswith("/*", i):
                depth += 1
                width = 2
            elif source.startswith("*/", i):
                depth -= 1
                width = 2
            else:
                width = 1
            for j in range(i, i + width):
                if source[j] != "\n":
                    out[j] = " "
            i += width
        elif delimiter:
            escape = "\\" + "#" * delimiter.count("#")
            if source.startswith(delimiter, i):
                i += len(delimiter)
                frames.pop()
            elif source.startswith(escape + "(", i):
                frames.append(("", 1))
                i += len(escape) + 1
            elif source.startswith(escape, i):
                i += len(escape) + 1
            else:
                i += 1
        elif source[i] == "#" and re.match(r"#+/", source[i:]):
            raise ValueError("extended regex literal requires lexer review")
        elif source.startswith("//", i):
            end = source.find("\n", i)
            end = len(source) if end < 0 else end
            out[i:end] = " " * (end - i)
            i = end
        elif source.startswith("/*", i):
            depth = 1
            out[i:i + 2] = "  "
            i += 2
        elif source[i] == "/" and i + 1 < len(source) and not source[i + 1].isspace():
            # Copaky: a regex can contain // and hide subsequent executable code
            # from a comment lexer. Reject ambiguous slash syntax, rather than
            # pretend to parse Swift regexes. Ordinary spaced division is safe.
            raise ValueError("ambiguous bare-slash syntax requires lexer review; use spaces for division")
        else:
            opening = re.match(r'(#+)?("""|")', source[i:]) if source[i] in '#"' else None
            if opening:
                frames.append((opening[2] + (opening[1] or ""), 0))
                i += len(opening[0])
            else:
                if parentheses and source[i] in "()":
                    parentheses += 1 if source[i] == "(" else -1
                    if parentheses:
                        frames[-1] = ("", parentheses)
                    else:
                        frames.pop()
                i += 1
    if depth or len(frames) != 1:
        raise ValueError("unterminated comment/string: cannot safely scan Swift source")
    return "".join(out)


def source_files(repo: Path) -> list[Path]:
    """Collect the fixed reviewed scope; missing inputs must never become PASS."""
    if not repo.is_dir():
        raise ValueError(f"not a repository directory: {repo}")
    for target in SHARED_TARGETS:
        folder = repo / "AzooKeyCore/Sources" / target
        if not folder.is_dir():
            raise ValueError(f"missing shared target: {folder.relative_to(repo)}")
    files = [repo / MANIFEST]

    def walk_error(error: OSError) -> None:
        raise error

    for relative in SOURCE_ROOTS:
        folder = repo / relative
        if not folder.is_dir() or folder.is_symlink():
            raise ValueError(f"missing or symlinked source root: {relative}")
        before = len(files)
        for current, dirs, names in os.walk(folder, onerror=walk_error):
            dirs.sort()
            for name in dirs + sorted(names):
                path = Path(current) / name
                if path.is_symlink():
                    raise ValueError(f"symlink in source scope: {path.relative_to(repo)}")
                if path.is_file() and path.suffix in NATIVE_SUFFIXES:
                    raise ValueError(f"unsupported native source requires scope review: {path.relative_to(repo)}")
            files.extend(Path(current) / name for name in sorted(names) if name.endswith(".swift"))
        if relative != SOURCE_ROOTS[2] and len(files) == before:
            raise ValueError(f"no Swift sources in required root: {relative}")
    for target in SHARED_TARGETS:
        if not any(path.is_relative_to(repo / "AzooKeyCore/Sources" / target) for path in files):
            raise ValueError(f"no Swift sources in shared target: {target}")
    return files


def audit(repo: Path) -> int:
    """Print a bounded-scope static verdict, retaining every finding and error."""
    print("Scope: local Keyboard + ALL AzooKeyCore/Sources targets + EmojiDictionary Swift sources;")
    print(f"       {MANIFEST} is scanned as build metadata with exact reviewed exceptions.")
    print("Excluded: MainApp-only code, test targets, build artifacts, external packages/binaries.")
    print("External dependency sources: NOT_SCANNED (AzooKeyKanaKanjiConverter, CustardKit and transitives).")
    print("Limit: reviewed source roots, lexical patterns only; re-review scope when target membership changes.")
    print("OFFLINE_RUNTIME=NOT_RUN")
    scanned = 0
    blocked = 0
    errors = []
    admitted = {key: 0 for key in ALLOWED_REFERENCES}
    try:
        files = source_files(repo)
    except (OSError, ValueError) as exc:
        files = []
        errors.append(str(exc))
    for path in files:
        relative = path.relative_to(repo).as_posix()
        try:
            if path.is_symlink():
                raise ValueError("symlinked source/manifest")
            source = path.read_text(encoding="utf-8")
            code = without_comments(source)
            original_lines = source.split("\n")
            for rule, pattern in PATTERNS:
                for match in pattern.finditer(code):
                    line_no = code.count("\n", 0, match.start()) + 1
                    key = (relative, rule, original_lines[line_no - 1].strip())
                    if key in ALLOWED_REFERENCES:
                        admitted[key] += 1
                        print(f"[ALLOW] {relative}:{line_no} {rule}: {ALLOWED_REFERENCES[key]}")
                    else:
                        blocked += 1
                        print(f"[BLOCK] {relative}:{line_no} {rule}")
            scanned += 1
        except (OSError, UnicodeError, ValueError) as exc:
            errors.append(f"{relative}: {exc}")
    # Stale/missing/duplicated exceptions are not silent holes in the reviewed scope.
    for key, count in admitted.items():
        if count != 1:
            errors.append(f"reviewed manifest reference must occur exactly once: {key[0]} {key[2]} (found {count})")
    for error in errors:
        print(f"[ERROR] {error}")
    status = "ERROR" if errors else "FAIL" if blocked else "PASS"
    print(f"Scanned Swift files: {scanned}; admitted references: {sum(admitted.values())}; blocked: {blocked}; errors: {len(errors)}")
    print(f"OFFLINE_STATIC={status}")
    return 2 if errors else 1 if blocked else 0


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: audit_network_calls.py <copaky_repository_root>")
        print("OFFLINE_RUNTIME=NOT_RUN\nOFFLINE_STATIC=ERROR")
        return 2
    try:
        return audit(Path(argv[1]).resolve())
    except (OSError, ValueError) as exc:
        print(f"[ERROR] {exc}")
        print("OFFLINE_RUNTIME=NOT_RUN\nOFFLINE_STATIC=ERROR")
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
