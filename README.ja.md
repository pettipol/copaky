# Copaky（日本語）

*[English](./README.md) · 日本語*

**Copaky** は、iPhone 向けのプライバシー重視の日本語キーボードで、**オフラインのクリップボード管理**機能
を備えています。[azooKey](https://github.com/azooKey/azooKey)（MIT）を基盤とする**独立したプロジェクト**で
あり、azooKey の高品質な日本語変換エンジンを活かしつつ、クリップボード・プライバシー・テレメトリの挙動を
徹底した**オンデバイス／ノーネットワーク**方針で作り直しています。

> **ステータス：プレリリース（v0.1）。** App Store 未公開です。初回提出に向けて、実機での検証と
> TestFlight でのドッグフーディングを進めています。**v0.1 は iPhone 専用**です。App Store は一度出荷した
> デバイスファミリーの削除を認めない（ITMS-90101）ため、iPad 対応は v0.2 に延期しています。

## azooKey をベースに

Copaky は **三輪敬太（ensan）**氏と azooKey コントリビューターの成果の上に成り立っています。キーボードの
大部分 — UI、かな漢字変換、カスタムキー／カスタムタブ — は azooKey 由来です。Copaky は独自のアイデンティティ
を持つ独立したプロジェクトであり、上流の成果に感謝し、しっかりとクレジットを記したうえで公開しています。
ぜひ上流プロジェクトを応援・参照してください：

- azooKey — https://github.com/azooKey/azooKey
- 変換エンジン AzooKeyKanaKanjiConverter — https://github.com/azooKey/AzooKeyKanaKanjiConverter
- macOS 版 azooKey-Desktop — https://github.com/azooKey/azooKey-Desktop

Copaky は変換エンジンの**フォーク** — https://github.com/pettipol/AzooKeyKanaKanjiConverter
（MIT。`AzooKeyCore/Package.swift` でリビジョン固定）— に対してビルドしています。フォークでの追加は
キーボード言語としてのイタリア語（`it_IT`）のみで、それ以外はすべて上流 azooKey の成果です。

完全な帰属表示とサードパーティライセンスは [CREDITS.ja.md](./CREDITS.ja.md) を参照してください。

## 機能

- **日本語 IME** — azooKey の変換エンジン（ライブ変換、カスタムキー／カスタムタブ）。
- **オフラインのクリップボード管理** — プライバシーに準拠した、**ユーザー操作起点**のクリップボード履歴。
  ペーストボードが変化した *こと* だけを検知し（メタデータのみ。「○○からペースト」バナーは出ません）、
  明示的なユーザー操作があったときにのみ値を読み取り・保存します。パスワード／セキュア入力欄は決して
  取得しません。
- **ラテン文字タブ — 英語とイタリア語** — 日本語と並ぶ QWERTY レイアウトは1つです。イタリア語は設定
  「イタリア語を使う」で有効化する方式（**既定はオフ**）。オンにすると言語キーが ja → en → it と巡回し、
  予測はイタリア語辞書から行われます。オフのときの挙動は従来どおりです。長押しで西欧のアクセント記号を
  入力できます（è é ê ë · ù ú û ü · ì í î ï · ò ó ô ö õ · à á â ä ã · ñ · ç）。
- **数字ヒント（任意）** — QWERTY 最上段の各キーに数字を小さく表示し、長押しで入力できます（**既定はオフ**）。
- **日本語・英語・イタリア語のインターフェース** — キーボード自身の機能ラベル（改行・空白・次候補・タブの
  「戻る」）も UI 言語に追従し、常に日本語という状態ではなくなりました。未対応の言語は英語にフォールバック
  します。
- **同梱テーマ3種** — Copaky Light／Dark／Red（azooKey のテーマエディタはそのまま利用できます）。
- **完全オフライン（v0.1）** — キーボード拡張も companion アプリも、**一切**ネットワーク通信を行いません。
  カスタードはローカルファイルからのみ読み込み（リモートダウンロードなし）、リモート辞書の取得もありません。
  クリップボード履歴は App Group コンテナ内に保存されます。テレメトリはありません。

## azooKey からの変更点

- プライバシー優先のクリップボード再設計（DETECT／CAPTURE の分離、セキュア入力欄ガード、項目サイズ上限、
  7 日で自動削除）。
- **完全オフライン化**：アプリ全体 — キーボード *および* companion — のネットワークコードを（スタブ化では
  なく）**削除**しました（GitHub の hotfix 辞書取得、リモートのカスタードのダウンロード・共有）。
- テレメトリ／「貢献」レポート機能を**削除**（データ収集なし）。
- azooKey → Copaky へのリブランド（bundle id、App Group、URL スキーム、表示名、UI テキスト）。ただし
  **azooKey のクレジットはすべて保持**しています。
- **Zenzai（ニューラル変換）は v2 に延期** — **v0.1 には含まれません**。v0.1 は azooKey のクラシックな
  （非ニューラル）かな漢字変換を使用します。`zenz` GGUF モデル（CC-BY-SA-4.0）は**バンドルしていない**ため、
  v0.1 の拡張は軽量で、App Store のバイナリに share-alike の重みを含みません。

## ビルド

最新の **Xcode** と（無料の）Apple Developer アカウントが必要です。本プロジェクトは git submodule を使用します。

```sh
git clone --recursive https://github.com/pettipol/copaky.git
cd copaky
open azooKey.xcodeproj      # その後 "MainApp" スキームをビルド＆実行
```

（Xcode プロジェクトのファイル名は上流のまま `azooKey.xcodeproj` です。）

コマンドライン（iOS シミュレータ）：

```sh
xcodebuild build -project azooKey.xcodeproj -scheme MainApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## ローカルファースト CI

これは iOS／UIKit アプリ（無料の Linux ランナーではビルド不可）であり、ホスト型の **macOS** CI は 10 倍で
課金されます。単独メンテナと高性能 Mac という条件では、ゲートは**ローカル**に置きます：

- [`scripts/ci-local.sh`](./scripts/ci-local.sh) — ビルド＋全テストスイートをミラーします（*ここで green
  なら CI も green*）。`--fast` はビルド＋クリップボードテストのみを実行します。
- pre-push フック：`git config core.hooksPath .githooks`（push 前に fast ゲートを実行。`git push
  --no-verify` で回避可能）。
- GitHub Actions のワークフローは残していますが、Actions の分数を消費しないよう **`workflow_dispatch`**
  （手動）に設定しています。[CONTRIBUTING.md](./CONTRIBUTING.md) を参照してください。

## ライセンス

Copaky は **MIT ライセンス**で公開しています — [LICENSE](./LICENSE) を参照してください。azooKey
（MIT, © 三輪敬太／ensan）および [CREDITS.ja.md](./CREDITS.ja.md) に記載のその他のサードパーティ
コンポーネントを含みます。
