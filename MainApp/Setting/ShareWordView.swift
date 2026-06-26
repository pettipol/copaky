//
//  ShareWordView.swift
//  azooKey
//
//  Created by ensan on 2023/04/15.
//  Copyright © 2023 ensan. All rights reserved.
//

import AzooKeyUtils
import SwiftUI

struct ShareWordView: View {
    @State private var word = ""
    @State private var ruby = ""
    @State private var note = ""
    @State private var sending = false
    @State private var shareUnavailable = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if sending {
                Section {
                    HStack {
                        Text("申請中です")
                        ProgressView()
                    }
                }
            }
            Section(footer: Text("\(systemImage: "doc.on.clipboard")を長押しでペースト")) {
                HStack {
                    TextField("単語", text: $word)
                    Divider()
                    PasteLongPressButton($word)
                        .padding(.horizontal, 5)
                }
                HStack {
                    TextField("読み", text: $ruby)
                    Divider()
                    PasteLongPressButton($ruby)
                        .padding(.horizontal, 5)
                }
            }

            HStack {
                TextField("備考", text: $note, prompt: Text("補足情報があれば記入してください"), axis: .vertical)
                Divider()
                PasteLongPressButton($note)
                    .padding(.horizontal, 5)
            }

            Section(footer: Text("この単語を他のユーザにも共有することを申請します。\n個人情報を含む単語は申請しないでください。")) {
                Button("申請する") {
                    Task {
                        self.sending = true
                        let shared = await SharedStore.sendSharedWord(word: word, ruby: ruby.toKatakana(), note: note, options: [])
                        self.sending = false
                        if shared {
                            dismiss()
                        } else {
                            // オフライン版では共有は無効。誤った「成功」表示（黙ってdismiss）を避けて通知する。
                            self.shareUnavailable = true
                        }
                    }
                }
                .disabled(word.isEmpty && ruby.isEmpty)
            }
        }
        .multilineTextAlignment(.leading)
        .navigationBarTitle(Text("変換候補の追加申請"), displayMode: .inline)
        .alert("オフラインのため共有できません", isPresented: $shareUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("このバージョンは完全オフラインで動作します。入力した単語は外部に送信されず、この端末にのみ保存されます。")
        }

    }
}
