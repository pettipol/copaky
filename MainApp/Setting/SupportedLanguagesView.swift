// Copaky: This Copaky-specific screen documents the bundled languages and their current limits.

import SwiftUI

struct SupportedLanguagesView: View {
    var body: some View {
        Form {
            Section("日本語") {
                LanguageFactRow("できること") {
                    Text("フリック入力とローマ字入力のかな漢字変換、ライブ変換、予測候補、絵文字、ユーザ辞書を利用できます。顔文字辞書とクリップボードタブは設定で追加できます。")
                }
                LanguageFactRow("使い方") {
                    Text("初回の既定は日本語タブです。QWERTYの言語キーは、イタリア語が有効なとき「あ」→「A」→「IT」の順に切り替わり、長押しで直接選べます。")
                }
                LanguageFactRow("現在の制限") {
                    Text("0.1にはニューラル変換モデルZenzaiは含まれません。今後のバージョンで対応予定です。")
                }
            }

            Section("英語") {
                LanguageFactRow("できること") {
                    Text("QWERTYのラテン文字タブでは、入力中に英語の予測候補を表示します。")
                }
                LanguageFactRow("使い方") {
                    Text("QWERTYの言語キーで「A」を選びます。イタリア語が有効なら長押しで直接選べます。「A」が選ばれている間はタブバーからラテン文字タブに戻れます。")
                }
                LanguageFactRow("現在の制限") {
                    Text("タイプミスはまだ自動修正されません。数字・記号タブは選択中のラテン文字言語に合わせて表示されます。")
                }
            }

            Section {
                LanguageFactRow("できること") {
                    Text("QWERTYのラテン文字タブでは、アクセント付きの語を含むイタリア語候補を表示します（例：「perche」→「perché」）。")
                }
                LanguageFactRow("使い方") {
                    Text("設定 ▸ 「イタリア語を使う」をオンにし、QWERTYの言語キーで「IT」を選びます。第一優先言語がイタリア語の端末では初期設定がオンです。")
                }
                LanguageFactRow("現在の制限") {
                    Text("語彙は今後の更新で拡充予定です。アクセントなしで入力した語は、スペースで辞書のアクセント付きの形に補正されます（「perche」→「perché」。設定でオフにできます）。他の形は候補から選んでください。")
                }
            } header: {
                Text("イタリア語")
            } footer: {
                Text("入力処理はすべてデバイス上で行われ、キーボード拡張はネットワーク接続を行いません。")
            }
        }
        .navigationTitle("対応言語")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Copaky: one fact of a language card — a small secondary caption above the sentence, stacked
/// so that long sentences read as prose instead of being squeezed into a trailing column.
/// Copaky: 言語カードの1項目 — 見出しを上、文章を下に重ねて長文でも読みやすくする。
private struct LanguageFactRow<Content: View>: View {
    private let caption: LocalizedStringKey
    private let content: Content

    init(_ caption: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
