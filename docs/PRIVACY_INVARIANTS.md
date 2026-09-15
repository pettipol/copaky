# Privacy invariants

*English · [日本語](./PRIVACY_INVARIANTS.ja.md)*

These are the **structural** properties Copaky claims — see [SECURITY.md](../SECURITY.md) for the
full "what this app claims, so you know what to attack" list they are drawn from. A pull request
must not break any of them without an explicit, reviewed reason. This is the checklist referenced
from the [PR template](../.github/PULL_REQUEST_TEMPLATE.md) and enforced (where a machine can
enforce it) by the [PR gate](../.github/workflows/pr-gate.yml) and the local test suite.

Each invariant states: what it means, how it is checked today, and what a PR must say if it
touches the area the invariant covers.

## 1. No network in the keyboard extension

**What it means.** Neither `Keyboard/` nor any shared extension code makes a network request.
There is no telemetry, no analytics, no remote configuration, no account. This backs the App
Store privacy label ("Data Not Collected") and is treated as non-negotiable.

**How it is checked.** `scripts/audit_network_calls.py` (advisory offline audit, part of the full
`scripts/ci-local.sh` run) scans for network APIs (`URLSession`, `Network.framework`, raw sockets)
reachable from extension targets.

**What a PR must state.** If it adds a dependency or code path anywhere near `Keyboard/`, say
explicitly whether it can reach the network, and why the audit script still reports clean.

## 2. No analytics or telemetry, anywhere in the app

**What it means.** No crash reporter, no usage analytics SDK, no A/B testing framework, in the app
or the extension. The only telemetry that exists is what Apple itself collects via TestFlight
(App Store Connect), which is Apple's infrastructure, not Copaky's.

**How it is checked.** Same audit as above, extended to the app target; also a manual dependency
review — nothing in `Package.swift` / the Xcode project's package graph should be an analytics
SDK.

**What a PR must state.** Any new third-party dependency must say what it does and confirm it
performs no network calls and collects no data.

## 3. Clipboard value read only on explicit user intent

**What it means.** The keyboard may detect *that* the system pasteboard changed (the change
counter, which is metadata) but reads its *contents* only when the user taps the capture control.
A code path that reads clipboard content without that user action is a vulnerability, not a
feature — this is also called out in SECURITY.md as one of the five properties worth attacking.

**How it is checked.** `ClipboardHistoryManagerTests` (part of the `AzooKeyCore` suite run by
`scripts/ci-local.sh`) and the PR checklist item "No clipboard value read without explicit user
intent" in the [PR template](../.github/PULL_REQUEST_TEMPLATE.md).

**What a PR must state.** If it touches clipboard capture code, name the user action that gates
the read, and which test covers it.

## 4. Nothing written outside the App Group container

**What it means.** Clipboard history and any other persisted state live inside the shared App
Group container (so the app and the extension can share it) and nowhere else — no writes to
arbitrary app-sandbox paths, no `UserDefaults.standard` for anything that should be shared or that
outlives a reinstall in an unexpected way.

**How it is checked.** Code review today (no automated check yet); a PR that adds a new persisted
value should say which container it lives in.

**What a PR must state.** For any new persisted value: which container, what triggers pruning
(size cap / retention window, if applicable), and whether it survives a reinstall (it should not,
for anything sensitive).

## 5. No logging of typed content

**What it means.** In **Release** builds, nothing that resembles what the user typed — words,
candidates, clipboard text — reaches `os_log`, `print`, a crash log, or any other sink that could
leave the device or persist beyond the app's own storage. Diagnostic logs may record *that* an event
happened (e.g. "autocorrect fired"), never the *content* involved. The only exception is the
`#if DEBUG`-guarded autocorrect log used by the device test protocol (it records the typed word and
the candidates): it is compiled out of Release and TestFlight builds, and a PR must not widen it.

**How it is checked.** Code review today; the DEBUG-only autocorrect log introduced during device
testing is scoped to build configuration and excluded from Release, but even in DEBUG it must not
be typed-content-identifying beyond what is needed to debug the false-correction rate.

**What a PR must state.** Any new log line near typing, conversion, or clipboard code: confirm it
does not include the actual typed/copied text, and whether it is DEBUG-only.

## 6. Secure fields are skipped

**What it means.** Content typed into password fields (`UITextInputTraits.isSecureTextEntry`) is
never captured into clipboard history and never logged.

**How it is checked.** `ClipboardHistoryManagerTests` includes a secure-field guard case; manual
verification during device rounds.

**What a PR must state.** If it changes how secure-field detection works, confirm the guard test
still passes and still covers the changed path.

## 7. User-facing strings are trilingual

**What it means.** Not a security invariant in the strict sense, but a correctness one with the
same "must not silently regress" character: every user-facing string in
`Resources/Localizable.xcstrings` needs Japanese, English **and** Italian — an empty translation
unit renders as a blank key on device, it does not fall back to the key name.

**How it is checked.** The String Catalog lint step in `scripts/ci-local.sh` (step "String Catalog
lint") and the corresponding PR template checklist item.

**What a PR must state.** Any new user-facing string: confirm all three locales are filled in, not
just the one you were testing in.

---

If you are unsure whether a change touches one of these, say so in the PR description rather than
guessing — the maintainer would rather answer a question than review a silent regression.
