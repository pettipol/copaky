//
//  ItalianKeyboardLanguageNews.swift
//  Copaky
//
//  New in Copaky: news entry for the Italian keyboard language, not part of azooKey upstream.
//

import SwiftUI

struct ItalianKeyboardLanguageNews: View {
    var body: some View {
        TipsContentView("使用する言語") {
            TipsContentParagraph {
                Text("イタリア語をキーボードの言語として選べるようになりました。")
                Text("設定の「使用する言語」は編集可能な一覧です。日本語は先頭に固定され、英語は常に有効です。イタリア語を有効にすると、英語との順番を並べ替えられます。")
                Text("QWERTYの言語キーは有効な言語を一覧の順に切り替えます。長押しすると直接選択メニューを開きます。")
                Text("イタリア語を選ぶと、ラテン文字タブの予測候補はイタリア語の辞書に切り替わります。")
            }
            TipsContentParagraph {
                Text("キー配列はローマ字入力のままで変わりません。")
                Text("à ù ì ò é などのアクセント付き文字は、対応するキーを長押しすることで入力できます。")
            }
        }
    }
}
