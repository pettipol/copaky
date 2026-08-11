# Copaky

*English · [日本語](./README.ja.md)*

**Copaky** is a privacy-focused Japanese keyboard for iPhone, with an **offline clipboard manager**.
It is an **independent project** built on — and crediting — [azooKey](https://github.com/azooKey/azooKey)
(MIT): it keeps azooKey's high-quality Japanese conversion engine while reworking the clipboard, privacy,
and telemetry behaviour around a strict **on-device, no-network** model.

> **Status: pre-release (v0.1).** Not on the App Store yet — real-device validation and TestFlight
> dogfooding are in progress ahead of the first submission. **v0.1 ships for iPhone only**: iPad is
> deferred to v0.2, because the App Store does not allow dropping a device family once it has been
> shipped (ITMS-90101).

## Based on azooKey

Copaky is built on the work of **Keita Miwa (ensan)** and the azooKey contributors. Most of the keyboard —
the UI, the kana-kanji conversion, the custom keys/tabs — comes from azooKey. Copaky is an independent
project with its own identity, released with gratitude and full credit to the upstream work. Please support
and refer to the upstream project:

- azooKey — https://github.com/azooKey/azooKey
- Conversion engine, AzooKeyKanaKanjiConverter — https://github.com/azooKey/AzooKeyKanaKanjiConverter
- macOS version, azooKey-Desktop — https://github.com/azooKey/azooKey-Desktop

Copaky builds against a **fork** of the conversion engine —
https://github.com/pettipol/AzooKeyKanaKanjiConverter (MIT, pinned by revision in
`AzooKeyCore/Package.swift`) — which adds Italian (`it_IT`) as a keyboard language. Everything else in
the engine is upstream azooKey's work.

See [CREDITS.md](./CREDITS.md) for the full attribution and third-party licenses.

## Features

- **Japanese IME** — azooKey's conversion engine (live conversion, custom keys / custom tabs).
- **Offline clipboard manager** — a privacy-compliant, **user-initiated** clipboard history. It detects
  *that* the pasteboard changed (metadata only — no "pasted from…" banner) and reads/stores the value only
  on an explicit user action. Password / secure fields are never captured.
- **Latin tab — English and Italian** — one QWERTY layout alongside Japanese. Italian is opt-in ("Use
  Italian" in Settings, **off by default**): when it is on, the language key cycles ja → en → it and
  predictions come from an Italian dictionary; when it is off, behaviour is unchanged. Long-press gives
  Western-European accents (è é ê ë · ù ú û ü · ì í î ï · ò ó ô ö õ · à á â ä ã · ñ · ç).
- **Optional number hints** — the QWERTY top row can show each digit above its letter and type it on a
  long press (**off by default**).
- **Interface in Japanese, English and Italian** — including the keyboard's own functional key labels
  (enter, space, next candidate, tab "back"), which follow the interface language instead of always being
  Japanese. Any other system language falls back to English.
- **Three bundled themes** — Copaky Light / Dark / Red, on top of azooKey's theme editor.
- **Offline-true (v0.1)** — **neither** the keyboard extension **nor** the companion app makes any network
  calls. Custards are imported from local files only (no remote download), and there is no remote dictionary
  fetch. Clipboard history lives in the App Group container. No telemetry.

## What Copaky changes vs. azooKey

- Privacy-first clipboard redesign (DETECT / CAPTURE split, secure-field guard, item-size cap, 7-day prune).
- **Offline-true**: all network code is **removed** across the app — keyboard *and* companion (GitHub
  hotfix-dictionary fetch, remote custard download, remote custard sharing) — not merely stubbed.
- Telemetry / "contribution" reporting is **removed** (no data collection).
- Rebrand azooKey → Copaky (bundle id, App Group, URL scheme, display name, UI text) **while keeping all
  azooKey credits**.
- **Zenzai (neural conversion) is deferred to v2** — it is **not part of v0.1**. v0.1 uses azooKey's classic
  (non-neural) kana-kanji conversion. The `zenz` GGUF model (CC-BY-SA-4.0) is **not bundled**, so the v0.1
  extension stays light and ships no share-alike weights in the App Store binary.

## Build

Requires a recent **Xcode** and a (free) Apple Developer account. The project uses git submodules.

```sh
git clone --recursive https://github.com/pettipol/copaky.git
cd copaky
open azooKey.xcodeproj      # then build & run the "MainApp" scheme
```

(The Xcode project keeps its upstream name, `azooKey.xcodeproj`.)

From the command line (iOS Simulator):

```sh
xcodebuild build -project azooKey.xcodeproj -scheme MainApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## Local-first CI

This is an iOS / UIKit app (it cannot build on free Linux runners), so hosted **macOS** CI is billed 10×.
With a single maintainer and a capable Mac, the gate is **local**:

- [`scripts/ci-local.sh`](./scripts/ci-local.sh) — mirrors build + the full test suite (*green here ==
  green*). `--fast` runs build + the clipboard tests only.
- Pre-push hook: `git config core.hooksPath .githooks` (runs the fast gate before every push; bypass with
  `git push --no-verify`).
- The GitHub Actions workflows are kept but set to **`workflow_dispatch`** (manual) to avoid burning
  Actions minutes. See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

Copaky is released under the **MIT License** — see [LICENSE](./LICENSE). It incorporates azooKey
(MIT, © Keita Miwa / ensan) and other third-party components listed in [CREDITS.md](./CREDITS.md).
