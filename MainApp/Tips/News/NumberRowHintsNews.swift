//
//  NumberRowHintsNews.swift
//  Copaky
//
//  New in Copaky: news entry for the QWERTY number-row hints, not part of azooKey upstream.
//

import SwiftUI

struct NumberRowHintsNews: View {
    var body: some View {
        TipsContentView("上段に数字を表示") {
            TipsContentParagraph {
                Text("ローマ字入力のQWERTYキーボードで、最上段のキーに小さく数字を表示できるようになりました。")
                Text("該当のキーを長押しすると、その数字を入力できます。")
            }
            TipsContentParagraph {
                Text("既定ではオフのオプション機能です。設定の「操作性」からいつでも有効・無効を切り替えられます。")
            }
            BoolSettingView(.enableNumberRowHints)
        }
    }
}
