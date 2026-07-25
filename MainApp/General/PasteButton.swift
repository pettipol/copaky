//
//  PasteButton.swift
//  MainApp
//
//  Created by ensan on 2020/12/07.
//  Copyright © 2020 ensan. All rights reserved.
//

import SwiftUI

struct PasteButton: View {
    @Binding private var text: String

    init(_ text: Binding<String>) {
        self._text = text
    }

    var body: some View {
        Button {
            if let string = UIPasteboard.general.string {
                text = string
            }
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
        .accessibilityLabel(Text("ペースト"))
    }
}

struct PasteLongPressButton: View {
    @Binding private var text: String

    init(_ text: Binding<String>) {
        self._text = text
    }

    var body: some View {
        Image(systemName: "doc.on.clipboard")
            .onLongPressGesture(minimumDuration: 0.5) {
                if let string = UIPasteboard.general.string {
                    MainAppFeedback.success()
                    text = string
                }
            }
            .foregroundStyle(.accentColor)
            .accessibilityLabel(Text("ペースト"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if let string = UIPasteboard.general.string {
                    MainAppFeedback.success()
                    text = string
                }
            }
    }
}
