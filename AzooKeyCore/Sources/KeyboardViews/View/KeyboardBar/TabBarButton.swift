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

    var body: some View {
        KeyboardBarButton<Extension>(label: .copakyMark) {
            self.action.registerAction(.setTabBar(.toggle), variableStates: variableStates)
        }
        .accessibilityLabel(Text("タブバーを開く"))
    }
}
