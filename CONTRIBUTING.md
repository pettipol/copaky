# Contributing to Copaky

*English · [日本語](./CONTRIBUTING.ja.md)*

Copaky is an **independent, open-source** keyboard for iOS, built on — and crediting —
[azooKey](https://github.com/azooKey/azooKey) (MIT). Issues and pull requests are welcome.

For engine / conversion-level topics, the upstream azooKey docs (`docs/`) remain the reference.

## Development setup

1. Clone with submodules (the project depends on them):
   ```sh
   git clone --recursive https://github.com/pettipol/copaky.git
   ```
2. Open `azooKey.xcodeproj` in a recent **Xcode** and run the **MainApp** scheme (a free Apple Developer
   account is enough for the Simulator).
3. **Building on a physical device?** Create a machine-local `Copaky.local.xcconfig` next to
   `Copaky.xcconfig` (it is gitignored) with your own Apple Developer team:
   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   ```
   Simulator builds work without it. The capture scripts under `scripts/` read the same file
   (or the `COPAKY_TEAM` environment variable).

## Local-first CI (the gate)

This is an iOS / UIKit app, so it cannot build on free Linux runners, and hosted **macOS** CI minutes are
billed 10×. The source of truth is therefore **local**:

- Full check: `scripts/ci-local.sh` (build MainApp + full `AzooKeyCore` test suite + advisory offline audit).
- Fast check: `scripts/ci-local.sh --fast` (build + `ClipboardHistoryManagerTests`).
- **Enable the git hooks once:**
  ```sh
  git config core.hooksPath .githooks
  ```
  Running `scripts/ci-local.sh` does this for you if you have not set it, since a hook nobody
  enables protects nobody. Two hooks live there:
  - **pre-commit** — scans the staged diff for secrets with [gitleaks](https://github.com/gitleaks/gitleaks)
    (`brew install gitleaks`). It **fails closed**: if gitleaks is missing the commit is blocked,
    because a scanner that silently skips is worse than no scanner. Override deliberately with
    `COPAKY_ALLOW_NO_GITLEAKS=1`.
  - **pre-push** — runs the fast check. Bypass a single push with `git push --no-verify`.

  This repository is public. A secret that reaches a public repository cannot be un-published by
  rewriting history — forks, clones and caches keep the old objects — so the only real remedy is
  rotating the secret. That is why the scan runs before the commit exists, not before the push.

**Always make `scripts/ci-local.sh` green before opening a pull request.**

## UI tests (Simulator — deliberate, not part of the gate)

`MainAppUITests/` (shared scheme **`CopakyUITests`**) drives an ordered campaign on the Simulator:
onboarding and Full Access, the clipboard tab, accent long-press, number hints, localized key labels and
the Italian language cycle. It is **not** run by `scripts/ci-local.sh` — the tests are ordered, share state
created by earlier tests, and need Simulator setup (a keyboard enabled in Settings, Full Access granted) —
so it is run deliberately rather than on every push.

```sh
scripts/serve_test_page.sh --daemon    # serves MainAppUITests/Fixtures on 127.0.0.1:8377
xcodebuild test -project azooKey.xcodeproj -scheme CopakyUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
scripts/serve_test_page.sh --stop
```

Without that server, every field-based test fails at "Safari webview did not load".

Two things **cannot** be proven on the Simulator and need a real device: the system paste dialog
(`UIPasteControl`, behind the `use_system_paste_control` setting) and the keyboard extension's real memory
budget.

## Hosted GitHub Actions

The workflows in `.github/workflows/` are intentionally set to **`workflow_dispatch`** (manual run only) to
avoid burning Actions minutes on macOS runners. Maintainers run them from the Actions tab when needed
(e.g. a full matrix or CodeQL pass before a release). Dependabot runs **monthly**.

## Conventions

- Match the style of the surrounding code.
- Keep the **keyboard extension offline** — no network APIs in `Keyboard/` or shared extension code
  (the offline invariant; `scripts/audit_network_calls.py` helps check it). This invariant backs the
  App Store privacy label ("Data Not Collected") and is non-negotiable.
- Keep clipboard capture **user-initiated** (never read the pasteboard value without explicit intent).
- User-facing **strings are trilingual**: Japanese (the catalog's source language), English and Italian in
  `Resources/Localizable.xcstrings` — a new string needs all three. Repository **documents stay bilingual**
  English + Japanese (`*.md` / `*.ja.md` pairs).
- Never translate a **typed character**. In the keyboard, `KeyLabelType.localizedText(_:)` marks a
  *functional label* (enter, space, next candidate, tab "back") whose payload is a catalog key; `.text(_:)`
  marks a character that is inserted as-is and must never be localized.
- Preserve azooKey and third-party **credits** (see [CREDITS.md](./CREDITS.md)).

## Known test debt

`AzooKeyUtilsTests/UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format`
is a **pre-existing upstream failure** (date-template literal quoting) and is skipped in the full local run
until triaged. It is unrelated to Copaky's changes.
