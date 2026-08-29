//
//  ContactView.swift
//  MainApp
//
//  Created by ensan on 2020/11/19.
//  Copyright © 2020 ensan. All rights reserved.
//

import SwiftUI

struct ContactView: View {
    var body: some View {
        Form {
            // These two used to point at upstream azooKey's Google Forms, inherited unchanged by
            // the fork — so every bug report and feature request a Copaky user filed went to
            // ensan's inbox, about a keyboard he did not build. Now they open Copaky's own issue
            // tracker, which is public.
            Section(footer: Text("お問い合わせ内容を選んでください。ブラウザでGitHubが開きます。")) {
                FallbackLink("不具合報告", destination: URL(string: "https://github.com/pettipol/copaky/issues/new/choose")!)
                FallbackLink("機能の改善・追加", destination: URL(string: "https://github.com/pettipol/copaky/issues/new/choose")!)
            }
            Section(footer: Text("その他の質問・連絡などはメールでお寄せください")) {
                FallbackLink("その他の質問・連絡など", destination: URL(string: "mailto:support@copaky.app")!, icon: .mail)
            }
        }
        .multilineTextAlignment(.leading)
        .navigationBarTitle(Text("お問い合わせ"), displayMode: .inline)

    }
}
