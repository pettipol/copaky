//
//  ItalianKeyboardLanguageNews.swift
//  Copaky
//
//  New in Copaky: news entry for the Italian keyboard language, not part of azooKey upstream.
//

import SwiftUI

struct ItalianKeyboardLanguageNews: View {
    var body: some View {
        TipsContentView("イタリア語を使う") {
            TipsContentParagraph {
                Text("イタリア語をキーボードの言語として選べるようになりました。")
                Text("設定の「操作性」にある「イタリア語を使う」をオンにすると、言語切替キーにイタリア語が加わり、ラテン文字タブの予測変換がイタリア語の辞書から行われます。")
            }
            TipsContentParagraph {
                Text("キー配列はローマ字入力のままで変わりません。")
                Text("à ù ì ò é などのアクセント付き文字は、対応するキーを長押しすることで入力できます。")
            }
            BoolSettingView(.enableItalianKeyboardLanguage)
        }
    }
}
