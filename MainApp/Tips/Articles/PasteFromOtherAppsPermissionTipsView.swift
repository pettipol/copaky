//
//  PasteFromOtherAppsPermissionTipsView.swift
//  azooKey
//
//  Created by ensan on 2023/04/01.
//  Copyright © 2023 ensan. All rights reserved.
//

import SwiftUI

struct PasteFromOtherAppsPermissionTipsView: View {
    var body: some View {
        TipsContentView("「ほかのAppからペースト」について") {
            TipsContentParagraph {
                Text("「クリップボードの履歴」や「ペーストボタン」の機能を利用している際、頻繁に「ペーストの許可」を求めるダイアログが出ることがあります。")
                TipsImage(.pasteRequestDialogue)
                Text("Copakyが履歴のために自動で確認するのは、クリップボードが更新されたかどうか（メタデータ）だけです。内容を読み取るのは「現在のクリップボードを追加」をタップしたときだけで、ペーストする際にもクリップボードの情報を利用します。")
            }
            TipsContentParagraph {
                Text("設定アプリで「ほかのAppからペースト」を「許可」にすることで、ダイアログが出なくなります。")
                Text("「ほかのAppからペースト」の項目は、Copaky が一度クリップボードを読み取った後にだけ設定アプリに現れます。まず「クリップボードの履歴」タブの「現在のクリップボードを追加」を 1 回タップし、最初に出る iOS のダイアログで「ペーストを許可」を選んでください。")
            }
            TipsContentParagraph {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("設定アプリを開く") {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                }
            }
            TipsContentParagraph {
                TipsImage(.pasteFromOtherAppsSetting)
            }
            TipsContentParagraph {
                Text("なお、クリップボードの内容が自動で取得されることはありません。取得はあなたのタップ操作のときだけで、取得したテキストはアプリ内でのみ利用されます。")
            }
        }
    }
}
