# Changelog

*English · [日本語](./CHANGELOG.ja.md)*

All notable changes to **Copaky** (an independent project based on azooKey). Format based on
[Keep a Changelog](https://keepachangelog.com/). Built on **azooKey** (v3.x line, MIT); see
[CREDITS.md](./CREDITS.md).

## [Unreleased] — pre-release, private (v0.1)

### Added
- **Offline clipboard manager**: privacy-first redesign with a DETECT (metadata-only, no "pasted from…"
  banner) / CAPTURE (read on explicit user intent) split, a secure-field guard (password fields are never
  captured), a per-item size cap (~50 KB), and a 7-day auto-prune. Pasteboard source and clock are injectable
  for tests (`ClipboardHistoryManagerTests`, 8/8 green).
- **Local-first CI**: `scripts/ci-local.sh` (+ `--fast`) and a `.githooks/pre-push` gate that mirror the
  build + tests on a local Mac.

### Changed
- **Offline-true**: removed **all** network code across the app, not just the keyboard extension — the
  companion app no longer fetches the GitHub hotfix dictionary nor downloads custards from the network;
  custards are imported from local files only.
- **Rebrand azooKey → Copaky**: bundle id (`com.pettipol.copaky*`), App Group, URL scheme (`copaky://`),
  display name, `IsASCIICapable=true`, custard associated-domains removed.
- **UI text rebrand**: user-facing strings azooKey → Copaky across onboarding, tips, settings, the String
  Catalog (ja + en), and `InfoPlist.xcstrings` (display name) — **while keeping all azooKey credits** (OSS
  license page, upstream GitHub links, "based on azooKey" wording).
- **Version** reconciled to **0.1** (`MARKETING_VERSION`) across all targets (was inconsistent 2.4.2 / 3.0.2).
- **CI cost**: hosted macOS GitHub Actions workflows set to `workflow_dispatch` (manual); Dependabot cadence
  daily → monthly.

### Removed
- **Zenzai → deferred to v2**: the neural-conversion feature is **not part of v0.1**. The `zenz` GGUF model
  (CC-BY-SA-4.0) is no longer bundled (submodules removed), and the entire Zenzai UI / toggle / settings and
  the Zenzai-only `copaky://` deep-link chain were removed. v0.1 ships azooKey's classic (non-neural)
  conversion only.
- **Telemetry** removed structurally: the contribution / misconversion-reporting / word-sharing subsystem is
  gone (no data collection, no residual code paths).
- **Remote custard sharing** removed: the `custard.azookey.com` dead path and `CustardShareHelper` were
  deleted, along with the remote custard download in the companion app.

### Fixed
- **Fail-soft App Group**: 7 force-unwrapped `containerURL(…)!` accesses now degrade gracefully instead of
  crashing if the container is unavailable.
- Honest UI: removed fake "shared/submitted" success states left by the offline stubbing.
- Deep-link scheme check in `ContentView` corrected to the registered `copaky` scheme.

### Known issues
- One **pre-existing upstream** test failure
  (`UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format`,
  date-template literal quoting) — inherited from azooKey, triage pending, skipped in the full local gate.

### Pending before any public release
- On-device validation: RSS / jetsam budget (≤ 40 MB), `UIPasteControl` paste flow, TestFlight.
- Security pass (fuzzing, repo-wide pasteboard audit).
- Copaky-owned Privacy Policy / Terms pages and final app-store assets.
