//
//  GettingStartedTipsView.swift
//  azooKey
//
// Copaky: keep the three-step onboarding guide always reachable. / 3ステップの案内を常に表示。
//

import SwiftUI

struct GettingStartedTipsView: View {
    var body: some View {
        TipsContentView("はじめに") {
            TipsContentParagraph {
                Text("1. キーボードを追加する")
                    .bold()
                Text("設定アプリで「一般」▸「キーボード」▸「キーボード」▸「新しいキーボードを追加」▸「Copaky」の順に進みます。")
                Text("これで、文字を入力するときにCopakyをキーボードとして選べるようになります。")
                TipsImage(.initSettingKeyboardImageHand)
                TipsImage(.initSettingAzooKeySwitchImageHand)
            }

            TipsContentParagraph {
                Text("2. フルアクセスを許可する")
                    .bold()
                Text("設定アプリで「一般」▸「キーボード」▸「キーボード」▸「Copaky」▸「フルアクセスを許可」をオンにします。")
                Text("フルアクセスを許可すると、Copakyの振動フィードバック、ペーストボタン、「クリップボードの履歴」タブを使えるようになります。")
                Text("データはすべてこの端末内にとどまり、キーボードはネットワーク接続を行わず、フルアクセスはいつでもオフにできます。")
                TipsImage(.fullAccessAlert)
            }

            TipsContentParagraph {
                Text("3. 「ほかのAppからペースト」を「許可」にする")
                    .bold()
                Text("設定アプリで「Copaky」▸「ほかのAppからペースト」▸「許可」の順に進みます。")
                Text("「ほかのAppからペースト」の項目は、Copaky が一度クリップボードを読み取った後にだけ設定アプリに現れます。まず「クリップボードの履歴」タブの「現在のクリップボードを追加」を 1 回タップし、最初に出る iOS のダイアログで「ペーストを許可」を選んでください。")
                Text("許可しないと、「クリップボードの履歴」タブがクリップボードを読み取るたびに、iOSのペースト確認ダイアログが表示されます。")
                TipsImage(.pasteRequestDialogue)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("設定アプリを開く") {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                }
                TipsImage(.pasteFromOtherAppsSetting)
            }

            TipsContentParagraph {
                Text("次にできること")
                    .bold()
                Text("設定の「使用する言語」は編集可能な一覧です。日本語は先頭に固定され、英語は常に有効です。イタリア語を有効にすると、英語との順番を並べ替えられます。")
                Text("QWERTYの言語キーは有効な言語を一覧の順に切り替えます。長押しすると直接選択メニューを開きます。")
                Text("クリップボードの履歴は、既定では文字タブの123キーの長押しで開きます。設定で #+= / ☆123 キーも追加できます。")
                NavigationLink("フルアクセスについて") {
                    FullAccessTipsView()
                }
                NavigationLink("「ほかのAppからペースト」について") {
                    PasteFromOtherAppsPermissionTipsView()
                }
            }
        }
    }
}
