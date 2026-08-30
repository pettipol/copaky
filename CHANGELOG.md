# Changelog

*English · [日本語](./CHANGELOG.ja.md)*

All notable changes to **Copaky** (an independent project based on azooKey). Format based on
[Keep a Changelog](https://keepachangelog.com/). Built on **azooKey** (v3.x line, MIT); see
[CREDITS.md](./CREDITS.md).

## [Unreleased] — pre-release (v0.1)

### Added
- **Apple-familiar Latin bottom row** (F-07): language 1.25 / access key 1.25 / space 5.0 / return 2.5 —
  a wide space bar, the return key as the ↵ icon in the plain-newline state, and no period key beside
  Space. Double-space types ". " (setting «Double-space for period», on by default; Backspace right after
  restores the two spaces).
- **Latin auto-capitalization** (F-04b, on by default): a one-shot Shift arms at a provable field start or
  after sentence-ending punctuation (including after Return), honouring the host field's autocapitalization
  type; manual Shift/Caps are never touched.
- **Space-slide sensitivity** (F-09): slow / medium / fast (1.0 / 0.7 / 0.45 key widths per step),
  default medium, under the existing space-slide switch.
- **Compact Latin keyboard by default** (F-05/E-12): the empty candidate bar now hides by default on the
  Latin tabs (Japanese keeps it — conversion lives there).
- **QWERTY by default for English/Italian** (F-01) on fresh installs; the Japanese layout stays flick and
  the onboarding picker now configures the Japanese layout only.
- **Explicit VoiceOver labels for image keys** (E-18): delete, numbers, shift/caps, paste, cursor bar,
  emoji controls and the new return icon no longer read OS-derived symbol names.
- **Hardened experimental Latin autocorrect** (F-04, still off by default): device-learned words are
  filtered out of the candidates, the winner is re-validated by a second oracle query, frequency-attested
  Italian words are never touched, and capitalized words are excluded from the general path.
- **Clipboard history in one gesture** (A-11, refined by F-06): with «Save clipboard history» on, a long
  press opens the Clipboard-history tab directly from the `123` key by default; the `#+=` (Latin tabs) and
  `☆123` (Japanese flick) keys can be added as long-press openers in Settings. A small badge marks the
  enabled keys; with the slot (or the history) off the long press keeps toggling the tab bar. The decision is evaluated at press time (`NumbersSlotLongPressDecision`,
  unit-tested), the layout is unchanged; the back key of the history tab returns to the previous tab and its long
  press opens the tab bar. The candidate-bar Copaky button is now hidden by default (Settings ▸ «Show the Copaky
  button in the candidate bar» brings it back); when the long press would open the history, the `123` / `#+=` /
  `☆123` key shows a small clipboard badge in its corner (A-12). A new option «Hide the suggestion bar when it is
  empty (Latin keyboards)» (E-12, now ON by default — F-05) collapses the bar row on the English/Italian tabs when there is
  nothing to show, lowering the keyboard.
- **Guide images per language** (A-09): the «Getting started» / Tips pictures of the iOS Settings screens now
  have English and Italian variants (light and dark), captured on the iPhone 17 Pro Max and composed with the
  same highlight + hand as the Japanese originals (`scripts/compose_guide_assets.py` in the workspace); the
  paste-permission dialog and Settings-row pictures are real iPhone captures in Italian (light + dark) and
  English (dark), and the onboarding Globe picture has English/Italian light + dark variants too.
- **Offline clipboard manager**: privacy-first redesign with a DETECT (metadata-only, no "pasted from…"
  banner) / CAPTURE (read on explicit user intent) split, a secure-field guard (password fields are never
  captured), a per-item size cap (~50 KB), and a 7-day auto-prune. Pasteboard source and clock are injectable
  for tests (`ClipboardHistoryManagerTests`, 8/8 green).
- **Local-first CI**: `scripts/ci-local.sh` (+ `--fast`) and a `.githooks/pre-push` gate that mirror the
  build + tests on a local Mac.
- **Italian interface**: a complete Italian translation of the string catalog (companion app and settings),
  produced with a review and a terminology pass.
- **Localized keyboard key labels**: functional labels — the enter key in all of its states, space,
  next-candidate, and the "back" key of the clipboard and emoji tabs — now follow the interface language
  instead of always being Japanese. A new `KeyLabelType.localizedText(String)` keeps the distinction
  explicit between a *label* (translated) and a *typed character* (never translated); the labels of the
  bundled custards are translated at the `CustardKeyLabelStyle` → `KeyLabelType` boundary.
- **Italian as a keyboard language** (setting "Use Italian", **on by default when the phone's first
  preferred system language is Italian, off elsewhere** — locale-aware default): Italian has no tab of its
  own — it shares the Latin tab with English (same layout, its own prediction dictionary) through
  `VariableStates.latinKeyboardLanguage`. With the setting on, the language key cycles ja → en → it; with it
  off, behaviour is exactly as before. Backed by a Copaky fork of the conversion engine that adds `it_IT`
  (Italian `UITextChecker`, Italian-only predictions, Latin-alphabet candidates) — see
  [CREDITS.md](./CREDITS.md).
- **Western-European accents** on QWERTY long-press: è é ê ë · ù ú û ü · ì í î ï · ò ó ô ö õ · à á â ä ã ·
  ñ · ç.
- **Number hints on the QWERTY top row** (**off by default**): each digit is shown above its letter and
  typed with a long press.
- **Three bundled preset themes**: Copaky Light / Dark / Red.
- **Settings "Essentials"**: settings now open on a short list (input style, live conversion, number hints,
  Italian, clipboard history, sound, haptics, key font size) with one toggle that reveals all 13 sections.
  Search **always** bypasses the split, so a query can never miss a row the short list happens to hide.
  14 rows gained Italian and English search keys next to the Japanese ones.
- **Copaky's own News entries**: Italian as a keyboard language, number hints, clipboard history.
- **System paste button — experimental, off by default, requires Full Access**: `SystemPasteControl` wraps
  Apple's `UIPasteControl`, so copied text arrives as an item provider and the pasteboard is **never read**
  (`captureProvidedText` shares every guard and cap with the existing capture path). Not validated yet: the
  system paste dialog does not exist on the Simulator, so it must be confirmed on a device.
- **UI test campaign** (`MainAppUITests`, scheme `CopakyUITests`) covering onboarding, the clipboard tab,
  accents, number hints, localized key labels and the Italian language cycle, plus
  `scripts/serve_test_page.sh` for the local fixture page.
- **Store-screenshot harness**: `scripts/store_screenshots.sh` and `scripts/seed_sim_clipboard.sh`.

### Changed
- **Offline-true**: removed **all** network code across the app, not just the keyboard extension — the
  companion app no longer fetches the GitHub hotfix dictionary nor downloads custards from the network;
  custards are imported from local files only.
- **Rebrand azooKey → Copaky**: bundle id (`com.pettipol.copaky*`), App Group, URL scheme (`copaky://`),
  display name, `IsASCIICapable=true`, custard associated-domains removed.
- **UI text rebrand**: user-facing strings azooKey → Copaky across onboarding, tips, settings, the String
  Catalog, and `InfoPlist.xcstrings` (display name) — **while keeping all azooKey credits** (OSS license
  page, upstream GitHub links, "based on azooKey" wording).
- **Version** reconciled to **0.1** (`MARKETING_VERSION`) across all targets (was inconsistent 2.4.2 / 3.0.2).
- **CI cost**: hosted macOS GitHub Actions workflows set to `workflow_dispatch` (manual); Dependabot cadence
  daily → monthly.
- **v0.1 is iPhone-only**: `TARGETED_DEVICE_FAMILY` narrowed to iPhone on the app and the keyboard
  extension. iPad is deferred to v0.2, after real-device validation — the App Store does not allow dropping
  a device family once it has shipped (ITMS-90101), so shipping universal would have been irreversible.
- **Fallback language is English**: the project's development region moved from Japanese to English, so a
  system language Copaky does not localize now falls back to English instead of Japanese.
- **Visual identity**: the CopakyMark replaces azooKey's mark in the app, onboarding and keyboard; the
  bundled instructional images were recaptured with Copaky branding; the app icon was rebalanced.
- **One azooKey credit sentence**: the credit, previously worded three different ways across four screens,
  is now a single sentence used verbatim, stating both the parentage and the non-affiliation. Copyright
  headers on inherited files are left untouched — attribution is owed on MIT code.
- **In-app legal links** now point to `copaky.app/privacy.html` and `copaky.app/terms.html`; both pages are
  live.
- **Bundled emoji dictionary** restored (E17.0) and bumped to `eb15a8d1`.
- **Clipboard history persistence** is versioned; accessibility labels are bilingual; smooth-delete gained
  an opt-out.
- **Signing**: `DEVELOPMENT_TEAM` moved out of the project file into a gitignored `Copaky.local.xcconfig`.
- **Export compliance**: `ITSAppUsesNonExemptEncryption=false` declared in the keyboard's Info.plist.
- **Upstream version gates** treat Copaky-era (0.x) installs as fresh (`isCopakyEra`).

### Removed
- **Zenzai → deferred to v2**: the neural-conversion feature is **not part of v0.1**. The `zenz` GGUF model
  (CC-BY-SA-4.0) is no longer bundled (submodules removed), and the entire Zenzai UI / toggle / settings and
  the Zenzai-only `copaky://` deep-link chain were removed. v0.1 ships azooKey's classic (non-neural)
  conversion only.
- **Telemetry** removed structurally: the contribution / misconversion-reporting / word-sharing subsystem is
  gone (no data collection, no residual code paths).
- **Remote custard sharing** removed: the `custard.azookey.com` dead path and `CustardShareHelper` were
  deleted, along with the remote custard download in the companion app.
- **Dead custard share-link code**: inert since the offline-true change, now deleted.

### Fixed
- **Japanese leaking into the English/Italian keyboard UI** (A-10): 23 user-facing strings had never been
  extracted into the String Catalog — the confirmation after switching on «Save clipboard history», the
  in-keyboard notice banners (title/description/buttons, now localized at the view), the long-press menu of
  the candidate bar and its toast, the emoji-tab category names and search placeholder. A new advisory lint
  (`scripts/lint_hardcoded_ja.py`, wired into `ci-local`) lists CJK literals that are not catalog keys.
- The Getting-started and paste-permission guides now say that the «Paste from Other Apps» entry appears in
  the Settings app only after Copaky has tried to paste once (A-02b).
- **Fail-soft App Group**: 7 force-unwrapped `containerURL(…)!` accesses now degrade gracefully instead of
  crashing if the container is unavailable.
- Honest UI: removed fake "shared/submitted" success states left by the offline stubbing.
- Deep-link scheme check in `ContentView` corrected to the registered `copaky` scheme.
- Top-row letters stay uppercase under Shift / Caps Lock while number hints are shown.
- First-run notice storm on the keyboard (legacy azooKey emoji migrations).
- Screenshot pipeline: the remaining fail-open paths (seed / cleanup / mapping) now fail loudly.

### Known issues
- One **pre-existing upstream** test failure
  (`UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format`,
  date-template literal quoting) — inherited from azooKey, triage pending, skipped in the full local gate.
- The language key has **no long-press menu**: with Italian enabled, the third language is reachable only by
  cycling through the key.

### Pending before any public release
- On-device validation: RSS / jetsam budget (≤ 40 MB), the system paste button (`UIPasteControl`) flow,
  TestFlight.
- Security pass (fuzzing, repo-wide pasteboard audit).
- Remaining App Store assets (the paste-flow screenshots).
