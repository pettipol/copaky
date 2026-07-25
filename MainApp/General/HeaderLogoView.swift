//
//  HeaderIconView.swift
//  MainApp
//
//  Created by ensan on 2020/10/03.
//  Copyright © 2020 ensan. All rights reserved.
//

import KeyboardViews
import SwiftUI

struct HeaderLogoView: View {
    private var iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 9) {
            CopakyMark(fontSize: iconSize * 0.75)
            Text(verbatim: "Copaky")
                .font(.system(size: iconSize * 0.62, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Copakyのロゴ")
    }
}

#Preview {
    HeaderLogoView()
}
