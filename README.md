# Copaky

*English · [日本語](./README.ja.md)*

**Copaky** is a privacy-focused Japanese keyboard for iOS / iPadOS, with an **offline clipboard manager**.
It is an **independent project** built on — and crediting — [azooKey](https://github.com/azooKey/azooKey)
(MIT): it keeps azooKey's high-quality Japanese conversion engine while reworking the clipboard, privacy,
and telemetry behaviour around a strict **on-device, no-network** model.

> **Status: private / pre-release (v0.1).** Not on the App Store yet. Real-device validation (memory/RSS
> budget, `UIPasteControl` paste flow) and the security pass are still pending; the repository is private
> for now.

## Based on azooKey

Copaky is built on the work of **Keita Miwa (ensan)** and the azooKey contributors. Most of the keyboard —
the UI, the kana-kanji conversion, the custom keys/tabs — comes from azooKey. Copaky is an independent
project with its own identity, released with gratitude and full credit to the upstream work. Please support
and refer to the upstream project:

- azooKey — https://github.com/azooKey/azooKey
- Conversion engine, AzooKeyKanaKanjiConverter — https://github.com/azooKey/AzooKeyKanaKanjiConverter
- macOS version, azooKey-Desktop — https://github.com/azooKey/azooKey-Desktop

See [CREDITS.md](./CREDITS.md) for the full attribution and third-party licenses.

## Features

- **Japanese IME** — azooKey's conversion engine (live conversion, custom keys / custom tabs).
- **Offline clipboard manager** — a privacy-compliant, **user-initiated** clipboard history. It detects
  *that* the pasteboard changed (metadata only — no "pasted from…" banner) and reads/stores the value only
  on an explicit user action. Password / secure fields are never captured.
- **QWERTY English** layout alongside Japanese.
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
git clone --recursive <repo-url>
cd azooKey
open azooKey.xcodeproj      # then build & run the "MainApp" scheme
```

From the command line (iOS Simulator):

```sh
xcodebuild build -project azooKey.xcodeproj -scheme MainApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## Local-first CI

This is an iOS / UIKit app (it cannot build on free Linux runners), so hosted **macOS** CI is billed 10×.
On a private, single-developer repo with a capable Mac, the gate is **local**:

- [`scripts/ci-local.sh`](./scripts/ci-local.sh) — mirrors build + the full test suite (*green here ==
  green*). `--fast` runs build + the clipboard tests only.
- Pre-push hook: `git config core.hooksPath .githooks` (runs the fast gate before every push; bypass with
  `git push --no-verify`).
- The GitHub Actions workflows are kept but set to **`workflow_dispatch`** (manual) to avoid burning
  Actions minutes. See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

Copaky is released under the **MIT License** — see [LICENSE](./LICENSE). It incorporates azooKey
(MIT, © Keita Miwa / ensan) and other third-party components listed in [CREDITS.md](./CREDITS.md).
