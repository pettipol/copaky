//
//  LargeTextView.swift
//  Keyboard
//
//  Created by ensan on 2020/09/21.
//  Copyright © 2020 ensan. All rights reserved.
//

import SwiftUI

@MainActor
struct LargeTextView: View {
    private let text: String
    private let height: CGFloat
    @Binding private var isViewOpen: Bool
    @EnvironmentObject private var variableStates: VariableStates

    init(text: String, height: CGFloat, isViewOpen: Binding<Bool>) {
        self.text = text
        self.height = height
        self._isViewOpen = isViewOpen
    }

    private var font: Font {
        Font.system(size: Design.largeTextViewFontSize(text, upsideComponent: variableStates.upsideComponent, orientation: variableStates.keyboardOrientation), weight: .regular, design: .serif)
    }

    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: true, content: {
                Text(Design.fonts.forceJapaneseFont(text: text))
                    .font(font)
            })
            Button {
                isViewOpen = false
            } label: {
                Label("閉じる", systemImage: "xmark")
            }.frame(width: nil, height: height * 0.15)
        }
        .background(Color.background)
        .frame(height: height, alignment: .bottom)
    }
}
