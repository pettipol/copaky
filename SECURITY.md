# Security Policy / セキュリティポリシー

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's [private vulnerability reporting](https://github.com/pettipol/copaky/security/advisories/new)
on this repository. If that is unavailable to you, email **support@copaky.app** with
`[copaky-security]` in the subject.

What to expect:

| | |
|---|---|
| First response | within **7 days** |
| Assessment and plan | within **30 days** |
| Credit | offered in the release notes and `CREDITS.md`, or anonymity if you prefer |

Copaky is maintained by one person as an unpaid project. These are honest targets, not a
commercial SLA — if a deadline slips you will be told, rather than left waiting.

## Scope

In scope: the keyboard extension, the companion app, the clipboard history storage, the build
and signing scripts in `scripts/`, and our fork of the conversion engine
([pettipol/AzooKeyKanaKanjiConverter](https://github.com/pettipol/AzooKeyKanaKanjiConverter)).

Out of scope: vulnerabilities in upstream [azooKey](https://github.com/azooKey/azooKey) that
Copaky merely inherits unchanged — report those upstream, and tell us so we can track them.

## What this app claims, so you know what to attack

These are the properties worth testing. Each is meant to hold structurally, not by policy:

1. **No network.** Neither the keyboard extension nor the app makes any network request. There
   is no telemetry, no analytics, no account, no remote configuration. Anything that contacts a
   server is a bug — a serious one. `scripts/audit_network_calls.py` runs in the local CI gate
   to keep it that way.
2. **The clipboard is read only on explicit user intent.** The keyboard detects *that* the
   pasteboard changed (a counter, which is metadata) but reads its *value* only when the user
   taps the capture control. A path that reads clipboard content without a user action is a
   vulnerability, not a feature.
3. **Secure fields are excluded.** Content typed into password fields is never captured into
   clipboard history.
4. **Clipboard history never leaves the device.** It lives in the app group container, is
   capped in size, and is pruned on a retention window.
5. **Full Access is optional.** Typing, Japanese conversion and themes all work without it. It
   gates only the optional clipboard history and haptic feedback.

If you can break any of the five, that is exactly what we want to hear about.

## Supported versions

Copaky is pre-release. Only the latest build is supported; there are no backported fixes yet.

---

## 脆弱性の報告（日本語）

**セキュリティ上の問題を公開 issue に書かないでください。**

このリポジトリの[非公開の脆弱性報告](https://github.com/pettipol/copaky/security/advisories/new)
からご報告ください。利用できない場合は、件名に `[copaky-security]` を入れて
**support@copaky.app** までメールをお願いします。

初回返信は **7日以内**、評価と対応方針は **30日以内**を目安としています。謝辞はリリースノートと
`CREDITS.md` に記載します（匿名をご希望の場合はそのように扱います）。個人が無償で開発している
プロジェクトのため、これは商用のSLAではなく誠実な目標です。遅れる場合はその旨をお伝えします。

**対象範囲**：キーボード拡張、コンパニオンアプリ、クリップボード履歴の保存、`scripts/` のビルド・
署名スクリプト、および変換エンジンの当プロジェクトのフォーク。上流 azooKey をそのまま引き継いだ
箇所は対象外です（上流へご報告のうえ、追跡できるようお知らせください）。

**このアプリが主張していること**（攻撃していただきたい対象）：
(1) 通信を一切行わない — テレメトリ・解析・アカウント・遠隔設定なし。
(2) クリップボードの「値」を読むのは、ユーザーが取り込みボタンを押したときだけ（変更の検知は
カウンターというメタデータのみ）。
(3) パスワード等の保護フィールドは履歴に取り込まない。
(4) クリップボード履歴は端末外に出ない（容量上限と保持期間による削除あり）。
(5) フルアクセスは任意 — 入力・変換・テーマはフルアクセスなしで動作する。

この5つのいずれかを破れるのであれば、それこそがお聞きしたい内容です。

**対応バージョン**：プレリリース段階のため、最新ビルドのみを対象としています。
