//
//  SpaceSlideCursorSettingRows.swift
//  MainApp
//

import AzooKeyUtils
import KeyboardViews
import SwiftUI

struct SpaceSlideCursorSettingRows: View {
    private static let sensitivities: [SpaceSlideCursorSensitivity] = [.slow, .medium, .fast]

    @State private var isEnabled: Bool
    @State private var sensitivity: SettingUpdater<SpaceSlideCursorSensitivitySetting>

    @MainActor init() {
        self._isEnabled = .init(initialValue: EnableSpaceSlideCursor.value)
        self._sensitivity = .init(initialValue: .init())
    }

    var body: some View {
        Group {
            BoolSettingView(.enableSpaceSlideCursor) { isEnabled = $0 }
            if isEnabled {
                Picker(SpaceSlideCursorSensitivitySetting.title, selection: $sensitivity.value) {
                    Text("遅め").tag(Self.sensitivities[0])
                    Text("中くらい").tag(Self.sensitivities[1])
                    Text("速め").tag(Self.sensitivities[2])
                }
                .onAppear {
                    sensitivity.reload()
                }
            }
        }
    }
}
