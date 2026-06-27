# Changelog

All notable changes to **Copaky** (the fork). Format based on
[Keep a Changelog](https://keepachangelog.com/). Forked from **azooKey** (v3.x line); see
[CREDITS.md](./CREDITS.md).

## [Unreleased] — pre-release, private

### Added
- **Offline clipboard manager**: privacy-first redesign with a DETECT (metadata-only, no "pasted from…"
  banner) / CAPTURE (read on explicit user intent) split, a secure-field guard (password fields are never
  captured), a per-item size cap (~50 KB), and a 7-day auto-prune. Pasteboard source and clock are injectable
  for tests (`ClipboardHistoryManagerTests`, 7/7 green).
- **Local-first CI**: `scripts/ci-local.sh` (+ `--fast`) and a `.githooks/pre-push` gate that mirror the
  build + tests on a local Mac.

### Changed
- **Rebrand azooKey → Copaky**: bundle id (`com.pettipol.copaky*`), App Group, URL scheme (`copaky://`),
  display name, `IsASCIICapable=true`, custard associated-domains removed.
- **UI text rebrand (A2)**: user-facing strings azooKey → Copaky across onboarding, tips, settings,
  the String Catalog (ja + en), and `InfoPlist.xcstrings` (display name) — **while keeping all azooKey
  credits** (OSS license page, upstream GitHub links, "based on azooKey" wording).
- **CI cost**: hosted macOS GitHub Actions workflows set to `workflow_dispatch` (manual); Dependabot
  cadence daily → monthly.

### Removed / Disabled
- **Telemetry**: the contribution / misconversion-reporting feature is disabled and hidden (no data
  collection); network paths in the keyboard extension are stubbed.
- The **Zenzai** neural model (`zenz`, CC-BY-SA-4.0) is not bundled; Zenzai is disabled by default.

### Fixed
- Honest UI: removed fake "shared/submitted" success states left by the offline stubbing.
- Deep-link scheme check in `ContentView` corrected to the registered `copaky` scheme.

### Known issues
- One **pre-existing upstream** test failure
  (`UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format`,
  date-template literal quoting) — inherited from azooKey, triage pending, skipped in the full local gate.

### Pending before any public release
- On-device validation: RSS / jetsam budget (≤ 40 MB), `UIPasteControl` paste flow, TestFlight.
- Security pass (fuzzing, repo-wide pasteboard audit).
- Copaky-owned Privacy Policy / Terms pages and an app icon set; replace the historical azooKey changelog
  view with a Copaky one.
