# Copaky への貢献

*[English](./CONTRIBUTING.md) · 日本語*

Copaky は [azooKey](https://github.com/azooKey/azooKey)（MIT）を基盤とし、その功績をクレジットする
**独立系オープンソース**の iOS キーボードです。Issue・プルリクエストを歓迎します。

変換エンジンなどエンジン層のトピックについては、上流 azooKey のドキュメント（`docs/`）が引き続き参照先です。

## 開発環境のセットアップ

1. サブモジュールを含めてクローンします（プロジェクトが依存しています）:
   ```sh
   git clone --recursive https://github.com/pettipol/copaky.git
   ```
2. 最近の **Xcode** で `azooKey.xcodeproj` を開き、**MainApp** スキームを実行します
   （シミュレータなら無料の Apple Developer アカウントで十分です）。
3. **実機でビルドする場合**: `Copaky.xcconfig` の隣に、自分の Apple Developer チームを記載した
   `Copaky.local.xcconfig`（gitignore 済み）を作成してください:
   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   ```
   シミュレータビルドはこのファイルなしで動作します。`scripts/` 配下のキャプチャスクリプトも
   同じファイル（または環境変数 `COPAKY_TEAM`）を読み取ります。

## ローカルファースト CI（ゲート）

iOS / UIKit アプリのため無料の Linux ランナーではビルドできず、ホスト型 **macOS** CI の分数は
10 倍で課金されます。そのため信頼できる情報源は**ローカル**です:

- フルチェック: `scripts/ci-local.sh`（MainApp ビルド + `AzooKeyCore` 全テスト + オフライン監査）。
- 高速チェック: `scripts/ci-local.sh --fast`（ビルド + `ClipboardHistoryManagerTests`）。
- **pre-push フックを一度有効化してください:**
  ```sh
  git config core.hooksPath .githooks
  ```
  push のたびに高速チェックが走ります。単発の回避は `git push --no-verify`。

**プルリクエストを開く前に、必ず `scripts/ci-local.sh` をグリーンにしてください。**

## UI テスト（シミュレータ。ゲートには含みません）

`MainAppUITests/`（共有スキーム **`CopakyUITests`**）は、シミュレータ上で順序付きのキャンペーンを実行します:
オンボーディングとフルアクセス、クリップボードタブ、長押しのアクセント記号、数字ヒント、ローカライズされた
キーラベル、イタリア語の言語巡回。これは `scripts/ci-local.sh` では**実行されません** — テストは順序依存で
前のテストが作った状態を共有し、シミュレータ側の準備（設定でキーボードを有効化、フルアクセスを許可）が
必要なため、push のたびではなく意図的に実行します。

```sh
scripts/serve_test_page.sh --daemon    # MainAppUITests/Fixtures を 127.0.0.1:8377 で配信
xcodebuild test -project azooKey.xcodeproj -scheme CopakyUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
scripts/serve_test_page.sh --stop
```

このサーバーがないと、入力欄を使うテストはすべて「Safari webview did not load」で失敗します。

シミュレータでは**証明できず**実機が必要なものが2つあります: システムのペーストダイアログ
（`UIPasteControl`。設定 `use_system_paste_control` の裏）と、キーボード拡張の実際のメモリ予算です。

## ホスト型 GitHub Actions

`.github/workflows/` のワークフローは、macOS ランナーの Actions 分数を浪費しないよう意図的に
**`workflow_dispatch`**（手動実行のみ）に設定されています。必要なとき（リリース前のフルマトリクスや
CodeQL 実行など）にメンテナが Actions タブから実行します。Dependabot は**月次**で動作します。

## 規約

- 周囲のコードのスタイルに合わせてください。
- **キーボード拡張はオフラインを維持**してください — `Keyboard/` および拡張の共有コードに
  ネットワーク API を入れないこと（オフライン不変条件。`scripts/audit_network_calls.py` が
  チェックの助けになります）。この不変条件は App Store のプライバシーラベル
  （「データは収集されません」）を支えるものであり、交渉の余地はありません。
- クリップボードの取得は**ユーザー起点**を維持してください（明示的な意図なしにペーストボードの
  値を読まないこと）。
- ユーザー向けの**文字列は3言語**です：日本語（カタログのソース言語）・英語・イタリア語を
  `Resources/Localizable.xcstrings` に用意します（新しい文字列は3言語すべて必要）。リポジトリの
  **ドキュメントは英日の2言語**のままです（`*.md` / `*.ja.md` のペア）。
- **入力される文字は決して翻訳しないでください。** キーボードでは `KeyLabelType.localizedText(_:)` が
  *機能ラベル*（改行・空白・次候補・タブの「戻る」）を表し、そのペイロードがカタログのキーになります。
  `.text(_:)` はそのまま挿入される文字であり、ローカライズしてはいけません。
- azooKey およびサードパーティの**クレジット**を保持してください（[CREDITS.ja.md](./CREDITS.ja.md) 参照）。

## 既知のテスト債務

`AzooKeyUtilsTests/UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format`
は**上流由来の既存の失敗**（日付テンプレートのリテラル引用の問題）で、トリアージまでフルローカル実行では
スキップされています。Copaky の変更とは無関係です。
