#!/usr/bin/env python3
"""Copaky — String Catalog lint.

Guards the one failure mode that is invisible in review and catastrophic on device:
a localization unit whose value is the EMPTY STRING.

The catalog's source language is Japanese, so it is tempting to read
`"ja": {"stringUnit": {"state": "translated", "value": ""}}` as "no translation needed,
fall back to the key". Foundation does NOT do that — it finds the key, returns "", and the
UI renders blank. Verified on the built extension: 戻る / 確定 / 完了 came back empty from
both `Bundle.localizedString(forKey:)` and `String(localized:)`, which since the key-label
localization means blank keycaps on a Japanese phone.

The correct way to say "this language uses the key as-is" is to OMIT the language unit.

Usage:  python3 scripts/lint_string_catalog.py [catalog.xcstrings ...]
Exit 1 on any offending entry.

コパキー用の文字列カタログlint。値が空の localization unit を禁止する
（Foundationは空文字をそのまま返すため、実機で表示が空になる）。
"""

import json
import sys
from pathlib import Path

DEFAULT = [
    Path(__file__).resolve().parent.parent / "Resources" / "Localizable.xcstrings",
    Path(__file__).resolve().parent.parent / "Resources" / "InfoPlist.xcstrings",
]


def lint(path: Path) -> list[str]:
    if not path.exists():
        return [f"{path}: file non trovato"]
    try:
        catalog = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"{path}: JSON non valido — {exc}"]

    problems: list[str] = []
    for key, entry in catalog.get("strings", {}).items():
        for lang, unit in (entry.get("localizations") or {}).items():
            value = (unit.get("stringUnit") or {}).get("value")
            if value == "":
                shown = key if len(key) <= 48 else key[:45] + "..."
                problems.append(
                    f'{path.name}: chiave {shown!r} — la lingua "{lang}" ha valore VUOTO. '
                    f'Rimuovi l\'intera unità "{lang}" per usare la chiave come testo.'
                )
    return problems


def main(argv: list[str]) -> int:
    paths = [Path(a) for a in argv[1:]] or DEFAULT
    problems: list[str] = []
    for path in paths:
        problems.extend(lint(path))

    if problems:
        print("✘ String Catalog lint: {} problemi".format(len(problems)))
        for p in problems[:40]:
            print("   " + p)
        if len(problems) > 40:
            print(f"   … e altri {len(problems) - 40}")
        return 1

    checked = ", ".join(p.name for p in paths)
    print(f"✓ String Catalog lint: nessun valore vuoto ({checked})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
