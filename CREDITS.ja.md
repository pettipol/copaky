# クレジットとサードパーティライセンス

*[English](./CREDITS.md) · 日本語*

Copaky は **azooKey をベースにした独立プロジェクト**であり、azooKey なしには存在しません。各コンポーネント
の正式なライセンス全文はアプリ内の **設定 → オープンソースソフトウェア（Acknowledgements）** に収録されて
います。本ファイルはその要約です。

## ベースプロジェクト

- **azooKey** — © 三輪敬太（ensan）およびコントリビューター。**MIT ライセンス。**
  https://github.com/azooKey/azooKey
  Copaky は azooKey のキーボード UI、日本語入力、カスタマイズ機能を、上流プロジェクトへの十分なクレジットと
  感謝とともに再利用しています。

## コアエンジン・ライブラリ

ライセンス名は言語非依存のため、表は英語版と共通です。

| コンポーネント | 役割 | ライセンス |
|---|---|---|
| [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) — 実際には Copaky の[フォーク](https://github.com/pettipol/AzooKeyKanaKanjiConverter)を使用 | かな漢字変換エンジン | MIT |
| [CustardKit](https://github.com/azooKey/CustardKit) | カスタムタブ／カスタムキーのデータ形式 | MIT |
| [SwiftyMarisa](https://github.com/komamitsu/SwiftyMarisa) / marisa-trie | LOUDS／trie 辞書検索 | BSD-2-Clause |
| [Swift Algorithms](https://github.com/apple/swift-algorithms) | ユーティリティ | Apache-2.0 |
| [Swift Collections](https://github.com/apple/swift-collections) | ユーティリティ | Apache-2.0 |
| Swift Numerics / swift-argument-parser | ユーティリティ | Apache-2.0 |
| swift-transformers (tokenizers / Jinja) | トークナイズ支援 | 上流を参照（Apache-2.0） |
| [llama.cpp](https://github.com/ggerganov/llama.cpp) | **Zenzai** ニューラル変換の CPU 推論 | MIT |

> **変換エンジンのフォークについて。** Copaky は上流の変換エンジンを直接リンクしていません。
> `AzooKeyCore/Package.swift` が https://github.com/pettipol/AzooKeyKanaKanjiConverter を固定リビジョン
> で参照しています。このフォークは azooKey の AzooKeyKanaKanjiConverter（MIT, © 三輪敬太／ensan および
> コントリビューター）に、Copaky の変更を1点だけ加えたものです — キーボード言語としての `it_IT`
> （同梱のイタリア語頻度辞書による予測〔下の表を参照〕、フォールバックとしてのイタリア語
> `UITextChecker`、ラテン文字の候補）。上流の著作権表示はすべて保持しており、フォークのコードも MIT です。

> **Zenzai は v2 に延期。** ニューラル変換は **Copaky v0.1 には含まれません**。v0.1 は azooKey のクラシック
> な（非ニューラル）変換を使用します。`zenz` GGUF モデル（**CC-BY-SA-4.0**）は v0.1 に**バンドルしていません**。
> 上表の `llama.cpp` / SwiftyMarisa はエンジンの任意機能 Zenzai 用の経路を示しています。ビルド 3 以降、変換パッケージは
> `ZenzaiCPU` トレイト**なし**で取り込んでおり、出荷されるキーボード拡張にはどちらもリンクされていません（`otool -L` /
> `nm` で確認: `llama.framework` なし、marisa シンボルなし）。Zenzai の本格統合は v2 で予定しています。

## 辞書・言語データ

| ソース | 用途 | ライセンス／告知 |
|---|---|---|
| [SudachiDict](https://github.com/WorksApplications/SudachiDict) | 基本語彙 | Apache-2.0 |
| IPAdic | 基本語彙 | NAIST ライセンス（アプリ内テキスト参照） |
| [MeCab](https://taku910.github.io/mecab/) | 形態素解析 | GPL／LGPL／BSD（トライライセンス） |
| [mecab-ipadic-NEologd](https://github.com/neologd/mecab-ipadic-neologd) | 固有名詞解析 | COPYING 参照 |
| [Mozc](https://github.com/google/mozc) | 一部データ | BSD-3-Clause, © 2010-2022 Google Inc. |
| [japanese-word2vec-model-builder](https://github.com/shiroyagicorp/japanese-word2vec-model-builder) | 変換精度 | LICENSE 参照 |
| [Emoji-IME-Dictionary](https://github.com/peaceiris/emoji-ime-dictionary) | 絵文字候補 | LICENSE 参照 |
| [Kaomojitoka to Google IME Dictionary](https://github.com/nikukyugamer/kaomojitoka-to-google-ime-dictionary) | 顔文字候補 | LICENSE 参照 |
| [Kaomojic](https://github.com/mika-f/kaomojic) | 顔文字候補 | LICENSE 参照 |
| [Leipzig Corpora Collection](https://wortschatz.uni-leipzig.de/en) | イタリア語頻度辞書（フォーク内の `it_words.txt`） | **CC BY** — © Universität Leipzig / Sächsische Akademie der Wissenschaften / InfAI（[利用条件](https://wortschatz.uni-leipzig.de/en/usage)）。詳細はフォークの `ITALIAN_LEXICON_LICENSE.md` |

帰属表示に漏れや誤りがあると思われる場合は、issue を立ててください。正確なライセンス全文については、
アプリ内の Acknowledgements 画面が引き続き信頼できる情報源です。
