## What this changes

<!-- One or two sentences. What behaviour is different after this PR, from a user's point of view? -->

## Why

<!-- The problem, not the solution. If it fixes an issue, link it: Fixes #123 -->

## How it was verified

<!-- Not "it builds". What did you actually run, and what did it say? -->

- [ ] `scripts/ci-local.sh` is green (or `--fast` for a small change — say which)
- [ ] Tested on: <!-- Simulator / device, iOS version, keyboard language -->

## Checklist

- [ ] **No network calls added.** Copaky makes none, in either the app or the extension — this is a
      structural guarantee users are asked to trust, not a preference. `scripts/audit_network_calls.py`
      runs in the full local gate.
- [ ] **No clipboard value read without explicit user intent.** Detecting *that* the pasteboard
      changed (the change counter) is fine; reading its *contents* outside a user-initiated capture
      is not.
- [ ] **New user-facing strings are in the String Catalog**, with no empty translation units — an
      empty unit renders as a *blank key*, it does not fall back to the key name. The lint in the
      gate checks this.
- [ ] **No secret, token, or personal path added.** The pre-commit hook scans staged changes; see
      CONTRIBUTING.md.
- [ ] If this changes a privacy-relevant behaviour, **SECURITY.md and the privacy pages still say
      the truth**.

<!-- Japanese and Italian are both welcome in PR descriptions. 日本語でも構いません。 -->
