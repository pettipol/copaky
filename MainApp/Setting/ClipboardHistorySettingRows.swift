//
//  ClipboardHistorySettingRows.swift
//  MainApp
//

import AzooKeyUtils
import KeyboardViews
import SwiftUI

struct ClipboardHistorySettingRows: View {
    @State private var isHistoryEnabled: Bool

    @MainActor init() {
        self._isHistoryEnabled = .init(initialValue: EnableClipboardHistoryManagerTab.value)
    }

    var body: some View {
        Group {
            BoolSettingView(.enableClipboardHistoryManagerTab) { isHistoryEnabled = $0 }
            if isHistoryEnabled {
                // Copaky [G-07]: keep the essential list compact while preserving slot controls.
                NavigationLink("詳しい設定") {
                    ClipboardLongPressSlotsSettingView()
                }
                .accessibilityIdentifier("clipboard-long-press-slots-settings-link")
            }
        }
    }
}
