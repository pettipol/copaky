//
//  ClipboardHistoryNews.swift
//  Copaky
//
//  New in Copaky: news entry for the offline clipboard history, not part of azooKey upstream.
//

import SwiftUI

struct ClipboardHistoryNews: View {
    var body: some View {
        TipsContentView("クリップボードの履歴を保存") {
            TipsContentParagraph {
                Text("コピーした文字列の履歴をキーボードに保存し、専用のタブからいつでも呼び出せるようになりました。")
                Text("既定ではオフのオプトイン機能で、有効化にはフルアクセスの許可が必要です。")
                Text("クリップボードの履歴は、既定では文字タブの123キーの長押しで開きます。設定で #+= / ☆123 キーも追加できます。")
            }
            TipsContentParagraph {
                Text("履歴はこの端末内にのみ保存され、外部に送信されることはありません。ネットワーク通信を一切行わない機能です。")
            }
            BoolSettingView(.enableClipboardHistoryManagerTab)
        }
    }
}
