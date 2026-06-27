# Contributing to Copaky

Copaky is currently a **private, pre-release** fork of [azooKey](https://github.com/azooKey/azooKey).
External contributions are not open yet — this guide documents the local workflow.

For engine / conversion-level topics, the upstream azooKey docs (`docs/`) remain the reference.

## Development setup

1. Clone with submodules (the project depends on them):
   ```sh
   git clone --recursive <repo-url>
   ```
2. Open `azooKey.xcodeproj` in a recent **Xcode** and run the **MainApp** scheme (a free Apple Developer
   account is enough for the Simulator).

## Local-first CI (the gate)

This is an iOS / UIKit app, so it cannot build on free Linux runners; hosted **macOS** CI is billed 10×.
Because this repo is private and single-developer, the source of truth is **local**:

- Full check: `scripts/ci-local.sh` (build MainApp + full `AzooKeyCore` test suite + advisory offline audit).
- Fast check: `scripts/ci-local.sh --fast` (build + `ClipboardHistoryManagerTests`).
- **Enable the pre-push hook once:**
  ```sh
  git config core.hooksPath .githooks
  ```
  It runs the fast check before every push. Bypass a single push with `git push --no-verify`.

**Always make `scripts/ci-local.sh` green before pushing.**

## Hosted GitHub Actions

The workflows in `.github/workflows/` are intentionally set to **`workflow_dispatch`** (manual run only) to
avoid burning Actions minutes on macOS runners. Run them from the Actions tab when needed (e.g. a full
matrix or CodeQL pass before a public release). Dependabot runs **monthly**.

## Conventions

- Match the style of the surrounding code.
- Keep the **keyboard extension offline** — no network APIs in `Keyboard/` or shared extension code
  (the offline invariant; `scripts/audit_network_calls.py` helps check it).
- Keep clipboard capture **user-initiated** (never read the pasteboard value without explicit intent).
- Preserve azooKey and third-party **credits** (see [CREDITS.md](./CREDITS.md)).

## Known test debt

`AzooKeyUtilsTests/UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format`
is a **pre-existing upstream failure** (date-template literal quoting) and is skipped in the full local run
until triaged. It is unrelated to Copaky's changes.
