//
//  TabBarButton.swift
//
//
//  Created by miwa on 2023/10/05.
//

import SwiftUI

struct TabBarButton<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    @Environment(\.userActionManager) private var action
    @EnvironmentObject private var variableStates: VariableStates
    private let compact: Bool
    private let contentHeight: CGFloat?

    init(compact: Bool = false, contentHeight: CGFloat? = nil) {
        self.compact = compact
        self.contentHeight = contentHeight
    }

    var body: some View {
        KeyboardBarButton<Extension>(label: .copakyMark, compact: compact, contentHeight: contentHeight) {
            self.action.registerAction(.setTabBar(.toggle), variableStates: variableStates)
        }
        .accessibilityLabel(Text("タブバーを開く"))
        // Copaky: identify the control itself, without aggregating the toolbar's previews.
        .accessibilityIdentifier("copaky-toolbar-menu")
    }
}
