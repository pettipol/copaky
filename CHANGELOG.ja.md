# 変更履歴（Changelog）

*[English](./CHANGELOG.md) · 日本語*

**Copaky**（azooKey をベースにした独立プロジェクト）の主な変更点。フォーマットは
[Keep a Changelog](https://keepachangelog.com/) に準拠。**azooKey**（v3.x 系、MIT）を基盤としています。
[CREDITS.ja.md](./CREDITS.ja.md) を参照してください。

## [未リリース] — プレリリース・非公開（v0.1）

### 追加
- **オフラインのクリップボード管理**：プライバシー優先の再設計。DETECT（メタデータのみ。「○○からペースト」
  バナーなし）／CAPTURE（明示的なユーザー操作で読み取り）の分離、セキュア入力欄ガード（パスワード欄は決して
  取得しない）、項目サイズ上限（約 50 KB）、7 日での自動削除。ペーストボードのソースとクロックはテスト用に
  注入可能（`ClipboardHistoryManagerTests`、8/8 グリーン）。
- **ローカルファースト CI**：ローカル Mac でビルド＋テストをミラーする `scripts/ci-local.sh`（＋`--fast`）と
  `.githooks/pre-push` ゲート。

### 変更
- **完全オフライン化**：キーボード拡張だけでなく、アプリ全体のネットワークコードを**すべて**削除。companion
  アプリは GitHub の hotfix 辞書を取得せず、カスタードをネットワークからダウンロードもしません。カスタードは
  ローカルファイルからのみ読み込みます。
- **azooKey → Copaky のリブランド**：bundle id（`com.pettipol.copaky*`）、App Group、URL スキーム
  （`copaky://`）、表示名、`IsASCIICapable=true`、カスタードの associated-domains を削除。
- **UI テキストのリブランド**：オンボーディング、ヒント、設定、String Catalog（ja＋en）、
  `InfoPlist.xcstrings`（表示名）のユーザー向け文字列を azooKey → Copaky に。ただし **azooKey のクレジットは
  すべて保持**（OSS ライセンスページ、上流 GitHub リンク、「azooKey をベースに」の記載）。
- **バージョン**を全ターゲットで **0.1**（`MARKETING_VERSION`）に統一（従来は 2.4.2／3.0.2 と不整合）。
- **CI コスト**：ホスト型 macOS の GitHub Actions ワークフローを `workflow_dispatch`（手動）に設定。
  Dependabot の頻度を daily → monthly に。

### 削除
- **Zenzai → v2 に延期**：ニューラル変換機能は **v0.1 には含まれません**。`zenz` GGUF モデル
  （CC-BY-SA-4.0）はバンドルしなくなり（submodule を削除）、Zenzai の UI／トグル／設定一式と、Zenzai 専用の
  `copaky://` ディープリンク連鎖も削除しました。v0.1 は azooKey のクラシックな（非ニューラル）変換のみを
  搭載します。
- **テレメトリ**を構造的に削除：貢献／誤変換レポート／単語共有のサブシステムを撤去（データ収集なし、残存
  コードパスなし）。
- **リモートのカスタード共有**を削除：`custard.azookey.com` のデッドパスと `CustardShareHelper` を削除し、
  companion アプリのリモートカスタードダウンロードも撤去。

### 修正
- **App Group の fail-soft 化**：7 箇所の強制アンラップ `containerURL(…)!` を、コンテナが利用できない場合
  でもクラッシュせずに穏やかに劣化するように変更。
- 正直な UI：オフライン化のスタブが残していた偽の「共有済み／送信済み」成功表示を削除。
- `ContentView` のディープリンクのスキーム判定を、登録済みの `copaky` スキームに修正。

### 既知の問題
- 上流由来の**既存**テスト失敗が 1 件
  （`UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format`、
  日付テンプレートのリテラルのクォート）— azooKey から継承。トリアージ待ちで、フルのローカルゲートでは
  スキップ。

### 公開前に残っている作業
- 実機検証：RSS／jetsam 予算（≤ 40 MB）、`UIPasteControl` の貼り付けフロー、TestFlight。
- セキュリティ点検（ファジング、リポジトリ全体のペーストボード監査）。
- Copaky 自身のプライバシーポリシー／利用規約ページと、最終的な App Store 用アセット。
