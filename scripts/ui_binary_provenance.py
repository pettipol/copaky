#!/usr/bin/env python3
"""Copaky: compare built and installed app/keyboard executable provenance."""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import sys
from pathlib import Path, PurePosixPath
from typing import Any
from xml.parsers.expat import ExpatError


CHUNK_SIZE = 1024 * 1024
COMPONENTS = (
    ("main", ".", "main_executable"),
    ("keyboard_extension", "PlugIns/Keyboard.appex", "keyboard_extension_executable"),
)


def _within(root: Path, candidate: Path) -> bool:
    """Reject symlinks or plist paths which escape the app bundle."""
    try:
        candidate.resolve(strict=False).relative_to(root.resolve(strict=True))
    except (OSError, RuntimeError, ValueError):
        return False
    return True


def _hash_file(path: Path) -> dict[str, Any]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        while chunk := source.read(CHUNK_SIZE):
            digest.update(chunk)
            size += len(chunk)
    return {"present": True, "sha256": digest.hexdigest(), "size_bytes": size}


def _error_record(reason: str) -> dict[str, Any]:
    return {"present": False, "error": reason}


def _inspect_bundle(app: Path, bundle_relative_path: str, side: str,
                    component: str) -> dict[str, Any]:
    """Read a bundle's executable metadata and hash its executable/debug dylib."""
    try:
        app_root = app.resolve(strict=True)
    except FileNotFoundError:
        return {"executable_name": None, "executable": _error_record("missing_bundle"),
                "debug_dylib": _error_record("missing_bundle"),
                "errors": [{"side": side, "component": component,
                            "relative_path": bundle_relative_path, "reason": "missing_bundle"}]}
    except OSError:
        return {"executable_name": None, "executable": _error_record("unreadable_bundle"),
                "debug_dylib": _error_record("unreadable_bundle"),
                "errors": [{"side": side, "component": component,
                            "relative_path": bundle_relative_path, "reason": "unreadable_bundle"}]}

    bundle = app_root if bundle_relative_path == "." else app_root / bundle_relative_path
    bundle_path_label = "main" if bundle_relative_path == "." else bundle_relative_path
    if not _within(app_root, bundle):
        reason = "bundle_path_escapes_app"
        return {"executable_name": None, "executable": _error_record(reason),
                "debug_dylib": _error_record(reason),
                "errors": [{"side": side, "component": component,
                            "relative_path": bundle_path_label, "reason": reason}]}
    if not bundle.is_dir():
        return {"executable_name": None, "executable": _error_record("missing_bundle"),
                "debug_dylib": _error_record("missing_bundle"),
                "errors": [{"side": side, "component": component,
                            "relative_path": bundle_path_label, "reason": "missing_bundle"}]}

    plist_path = bundle / "Info.plist"
    plist_label = f"{bundle_path_label}/Info.plist"
    errors: list[dict[str, str]] = []
    executable_name: str | None = None
    if not _within(app_root, plist_path):
        errors.append({"side": side, "component": component,
                       "relative_path": plist_label, "reason": "plist_path_escapes_app"})
    elif not plist_path.is_file():
        errors.append({"side": side, "component": component,
                       "relative_path": plist_label, "reason": "missing_info_plist"})
    else:
        try:
            with plist_path.open("rb") as source:
                info = plistlib.load(source)
            name = info.get("CFBundleExecutable") if isinstance(info, dict) else None
            if (not isinstance(name, str) or not name or name in {".", ".."}
                    or PurePosixPath(name).name != name or "/" in name or "\\" in name):
                errors.append({"side": side, "component": component,
                               "relative_path": plist_label,
                               "reason": "invalid_cf_bundle_executable"})
            else:
                executable_name = name
        except (OSError, plistlib.InvalidFileException, ExpatError, ValueError, OverflowError):
            errors.append({"side": side, "component": component,
                           "relative_path": plist_label, "reason": "unreadable_info_plist"})

    executable = _error_record("unavailable_executable_name")
    debug = _error_record("unavailable_executable_name")
    if executable_name is not None:
        executable_path = bundle / executable_name
        executable_label = f"{bundle_path_label}/{executable_name}"
        executable = _inspect_binary(app_root, executable_path, executable_label,
                                      side, component, errors, missing_reason="missing_binary")

        debug_name = f"{executable_name}.debug.dylib"
        debug_path = bundle / debug_name
        debug_label = f"{bundle_path_label}/{debug_name}"
        debug = _inspect_optional_binary(app_root, debug_path, debug_label,
                                         side, component, errors)

    return {"executable_name": executable_name, "executable": executable,
            "debug_dylib": debug, "errors": errors}


def _inspect_binary(root: Path, path: Path, label: str, side: str, component: str,
                    errors: list[dict[str, str]], *, missing_reason: str) -> dict[str, Any]:
    if not _within(root, path):
        reason = "binary_path_escapes_app"
        errors.append({"side": side, "component": component,
                       "relative_path": label, "reason": reason})
        return _error_record(reason)
    if not path.exists():
        errors.append({"side": side, "component": component,
                       "relative_path": label, "reason": missing_reason})
        return _error_record(missing_reason)
    if not path.is_file():
        reason = "binary_not_regular_file"
        errors.append({"side": side, "component": component,
                       "relative_path": label, "reason": reason})
        return _error_record(reason)
    try:
        return _hash_file(path)
    except OSError:
        reason = "unreadable_binary"
        errors.append({"side": side, "component": component,
                       "relative_path": label, "reason": reason})
        return _error_record(reason)


def _inspect_optional_binary(root: Path, path: Path, label: str, side: str,
                             component: str, errors: list[dict[str, str]]) -> dict[str, Any]:
    if path.is_symlink() or not _within(root, path):
        reason = "debug_binary_path_escapes_app" if not _within(root, path) else "debug_binary_symlink"
        errors.append({"side": side, "component": component,
                       "relative_path": label, "reason": reason})
        return _error_record(reason)
    if not path.exists():
        return {"present": False}
    if not path.is_file():
        reason = "debug_binary_not_regular_file"
        errors.append({"side": side, "component": component,
                       "relative_path": label, "reason": reason})
        return _error_record(reason)
    try:
        return _hash_file(path)
    except OSError:
        reason = "unreadable_debug_binary"
        errors.append({"side": side, "component": component,
                       "relative_path": label, "reason": reason})
        return _error_record(reason)


def _compare_asset(component: str, relative_paths: dict[str, str],
                   built: dict[str, Any], installed: dict[str, Any], *,
                   names_match: bool | None = None, optional: bool = False) -> dict[str, Any]:
    if optional:
        presence_match = built.get("present") == installed.get("present")
        content_match = None
        if built.get("present") and installed.get("present"):
            content_match = built.get("sha256") == installed.get("sha256")
        match = presence_match and (content_match is not False)
        return {"component": component, "relative_paths": relative_paths,
                "built": built, "installed": installed,
                "presence_match": presence_match, "content_match": content_match,
                "match": match}

    match = (built.get("present") is True and installed.get("present") is True
             and built.get("sha256") == installed.get("sha256")
             and names_match is True)
    result = {"component": component, "relative_paths": relative_paths,
              "built": built, "installed": installed, "match": match}
    if names_match is not None:
        result["executable_names_match"] = names_match
    return result


def compare_bundles(built_app: Path, installed_app: Path) -> dict[str, Any]:
    """Create a public-safe receipt comparing main and keyboard executable bytes."""
    comparisons: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []

    for role, bundle_relative_path, executable_component in COMPONENTS:
        built = _inspect_bundle(built_app, bundle_relative_path, "built", executable_component)
        installed = _inspect_bundle(installed_app, bundle_relative_path, "installed", executable_component)
        errors.extend(built["errors"])
        errors.extend(installed["errors"])
        built_exec_name = built["executable_name"]
        installed_exec_name = installed["executable_name"]
        built_bundle_label = role if role == "main" else bundle_relative_path
        installed_bundle_label = built_bundle_label
        built_exec_label = (f"{built_bundle_label}/{built_exec_name}"
                            if built_exec_name else f"{built_bundle_label}/<unavailable>")
        installed_exec_label = (f"{installed_bundle_label}/{installed_exec_name}"
                                if installed_exec_name else f"{installed_bundle_label}/<unavailable>")
        names_match = (built_exec_name == installed_exec_name
                       if built_exec_name is not None and installed_exec_name is not None else None)
        comparisons.append(_compare_asset(
            executable_component,
            {"built": built_exec_label, "installed": installed_exec_label},
            built["executable"], installed["executable"], names_match=names_match,
        ))

        debug_component = f"{role}_debug_dylib"
        built_debug_name = (f"{built_exec_name}.debug.dylib" if built_exec_name else None)
        installed_debug_name = (f"{installed_exec_name}.debug.dylib" if installed_exec_name else None)
        built_debug_label = (f"{built_bundle_label}/{built_debug_name}"
                             if built_debug_name else f"{built_bundle_label}/<unavailable>.debug.dylib")
        installed_debug_label = (f"{installed_bundle_label}/{installed_debug_name}"
                                 if installed_debug_name else f"{installed_bundle_label}/<unavailable>.debug.dylib")
        comparisons.append(_compare_asset(
            debug_component,
            {"built": built_debug_label, "installed": installed_debug_label},
            built["debug_dylib"], installed["debug_dylib"], optional=True,
        ))

    status = "PASS" if not errors and all(row["match"] for row in comparisons) else "FAIL"
    return {"schema_version": 1, "status": status,
            "comparison": "built_app_vs_installed_app",
            "comparisons": comparisons, "errors": errors}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("built_app", type=Path, help="built .app bundle")
    parser.add_argument("installed_app", type=Path, help="installed .app bundle copy")
    parser.add_argument("--out", type=Path, required=True, help="receipt JSON output path")
    args = parser.parse_args(argv)

    receipt = compare_bundles(args.built_app, args.installed_app)
    try:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n",
                            encoding="utf-8")
    except OSError:
        print("could not write binary provenance receipt", file=sys.stderr)
        return 2
    print(json.dumps(receipt, ensure_ascii=False, indent=2))
    return 0 if receipt["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
