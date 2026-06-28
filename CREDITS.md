# Credits & Third-Party Licenses

*English · [日本語](./CREDITS.ja.md)*

Copaky is an **independent project built on azooKey** and would not exist without it. The authoritative,
per-component license texts are bundled in the app under **Settings → オープンソースソフトウェア
(Acknowledgements)**; this file is a consolidated summary.

## Base project

- **azooKey** — © Keita Miwa (ensan) and contributors. **MIT License.**
  https://github.com/azooKey/azooKey
  Copaky reuses azooKey's keyboard UI, Japanese input, and customization features, with full credit and
  gratitude to the upstream project.

## Core engine & libraries

| Component | Role | License |
|---|---|---|
| [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) | Kana-kanji conversion engine | MIT |
| [CustardKit](https://github.com/azooKey/CustardKit) | Custom-tab / custom-key data format | MIT |
| [SwiftyMarisa](https://github.com/komamitsu/SwiftyMarisa) / marisa-trie | LOUDS / trie dictionary lookup | BSD-2-Clause |
| [Swift Algorithms](https://github.com/apple/swift-algorithms) | Utilities | Apache-2.0 |
| [Swift Collections](https://github.com/apple/swift-collections) | Utilities | Apache-2.0 |
| Swift Numerics / swift-argument-parser | Utilities | Apache-2.0 |
| swift-transformers (tokenizers / Jinja) | Tokenization support | see upstream (Apache-2.0) |
| [llama.cpp](https://github.com/ggerganov/llama.cpp) | CPU inference for **Zenzai** neural conversion | MIT |

> **Zenzai is deferred to v2.** Neural conversion is **not part of Copaky v0.1**: v0.1 uses azooKey's classic
> (non-neural) conversion. The `zenz` GGUF model (**CC-BY-SA-4.0**) is **not bundled** with v0.1. The
> `llama.cpp` dependency is still linked through the converter package (the `ZenzaiCPU` trait) but is **not
> invoked** in v0.1; full Zenzai integration is planned for v2.

## Dictionary & linguistic data

| Source | Use | License / notice |
|---|---|---|
| [SudachiDict](https://github.com/WorksApplications/SudachiDict) | Base vocabulary | Apache-2.0 |
| IPAdic | Base vocabulary | NAIST license (see in-app text) |
| [MeCab](https://taku910.github.io/mecab/) | Morphological analysis | GPL / LGPL / BSD (tri-license) |
| [mecab-ipadic-NEologd](https://github.com/neologd/mecab-ipadic-neologd) | Proper-noun analysis | see COPYING |
| [Mozc](https://github.com/google/mozc) | Partial data | BSD-3-Clause, © 2010-2022 Google Inc. |
| [japanese-word2vec-model-builder](https://github.com/shiroyagicorp/japanese-word2vec-model-builder) | Conversion accuracy | see LICENSE |
| [Emoji-IME-Dictionary](https://github.com/peaceiris/emoji-ime-dictionary) | Emoji candidates | see LICENSE |
| [Kaomojitoka to Google IME Dictionary](https://github.com/nikukyugamer/kaomojitoka-to-google-ime-dictionary) | Kaomoji candidates | see LICENSE |
| [Kaomojic](https://github.com/mika-f/kaomojic) | Kaomoji candidates | see LICENSE |

If you believe an attribution is missing or incorrect, please open an issue. The in-app Acknowledgements
screen remains the source of truth for the exact license texts.
