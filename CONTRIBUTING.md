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
- **Enable the pre-push hook once:**
  ```sh
  git config core.hooksPath .githooks
  ```
  It runs the fast check before every push. Bypass a single push with `git push --no-verify`.

**Always make `scripts/ci-local.sh` green before opening a pull request.**

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
- User-facing strings and documents are **bilingual English + Japanese** (`Localizable.xcstrings`;
  `*.md` / `*.ja.md` pairs).
- Preserve azooKey and third-party **credits** (see [CREDITS.md](./CREDITS.md)).

## Known test debt

`AzooKeyUtilsTests/UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format`
is a **pre-existing upstream failure** (date-template literal quoting) and is skipped in the full local run
until triaged. It is unrelated to Copaky's changes.
