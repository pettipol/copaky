# Copaky — Roadmap

*English · [日本語](./ROADMAP.ja.md)*

This is a direction, not a promise — plans change, and nothing here is a commitment to a release
date. Dates only appear next to things that are already built; everything else is ordered by how
close it is, not when it will land. (The same text lives on the public site,
[copaky.app/roadmap](https://copaky.app/roadmap.html) — this file mirrors it for people who read
the repo instead of the site.)

## Now

- Offline clipboard history: opt-in, pin support, automatic 7-day expiry for anything unpinned,
  and a guard that skips secure fields entirely.
- Long-press accents on the Latin keyboard ordered for how they're actually used (è before é, and
  the same idea for the other vowels).
- Numbers on the Latin keyboard, both flavors off by default: hint digits above the letters, or a
  real dedicated number row.
- An editable "Active languages" list that controls the language-switch cycle — and a language key
  that shows which language comes next.
- Slide the space bar to move the cursor, on the alphabetic QWERTY layouts (opt-in, off by default
  while on trial; flick layouts unchanged).
- "Use Italian" (on by default when the phone's first preferred language is Italian, off
  elsewhere): adds Italian to the language-switch key with suggestions from an Italian dictionary,
  without changing the key layout.
- Three built-in themes (Light, Dark, Red), and custom tabs imported from local files only — no
  network download.

## Next

- Deciding the defaults for the experimental extras — the space-bar cursor slide and the Latin
  typo correction — based on how they hold up in real use.
- An "Essentials" view in Settings for people who just want the basics, with the full list of
  sections still one tap away.
- Settings search that actually understands Italian and English terms, not just Japanese ones.
- One consistent, clearly labeled credits section, instead of the same acknowledgement worded
  differently across a few screens.

## Further out

- Full predictive typing for Italian — today "Use Italian" adds dictionary suggestions and
  long-press accents, not full word prediction yet.
- A way to move your personal dictionary between devices without needing a cloud account.
- iPad-specific refinements — the current focus has been the iPhone experience.
- Accessibility passes — Dynamic Type and VoiceOver label order — as a standing part of testing
  every release, not a one-off.

## Where help is welcome

This is a one-maintainer project, so contributions that fit into a small, well-scoped review are
the ones most likely to land. Areas where outside help is genuinely useful:

- **Italian and English typo corpora.** Test data only (a list of `(typo, correction)` pairs used
  to evaluate the autocorrect false-correction rate), MIT-licensed like the rest of the repo — not
  a personal dictionary or anything that could contain private text.
- **Translation review.** The catalog is Japanese/English/Italian
  (`Resources/Localizable.xcstrings`); a native-speaker pass on any of the three, especially
  Italian, is welcome.
- **Device testing reports.** Real hardware behaves differently from the Simulator — the
  [TestFlight beta feedback form](.github/ISSUE_TEMPLATE/beta-feedback.yml) is the fastest way to
  report what you found on your device.
- **Accessibility audits with VoiceOver.** Dynamic Type sizing and VoiceOver label order/content on
  the keyboard and the app are an open area (see "Further out" above).

Every contribution — code or test data — goes through the same local gate everyone else uses:
`scripts/ci-local.sh` must be green before a pull request is opened (see CONTRIBUTING.md).

---

Have a request, or notice something missing? Tell us at **support@copaky.app**, or open a
[feature idea in Discussions](https://github.com/pettipol/copaky/discussions/categories/ideas) —
most of what's on this page started as something someone told us they needed.
