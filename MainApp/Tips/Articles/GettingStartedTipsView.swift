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
                Text("言語キーで日本語・英語・イタリア語を切り替えられ、長押しするとメニューから選べます。")
                Text("イタリア語の予測変換を使うには、設定 ▸ 「イタリア語を使う」をオンにしてください。")
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
