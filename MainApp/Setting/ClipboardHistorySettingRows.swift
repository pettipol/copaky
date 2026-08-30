//
//  ClipboardHistorySettingRows.swift
//  MainApp
//

import AzooKeyUtils
import KeyboardViews
import SwiftUI

struct ClipboardHistorySettingRows: View {
    @State private var isHistoryEnabled: Bool
    @State private var slots: SettingUpdater<ClipboardLongPressSlotsSetting>

    @MainActor init() {
        self._isHistoryEnabled = .init(initialValue: EnableClipboardHistoryManagerTab.value)
        self._slots = .init(initialValue: .init())
    }

    var body: some View {
        Group {
            BoolSettingView(.enableClipboardHistoryManagerTab) { isHistoryEnabled = $0 }
            if isHistoryEnabled {
                Text(ClipboardLongPressSlotsSetting.title)
                    .font(.subheadline)
                Toggle("123キー（文字）", isOn: binding(for: .qwertyNumbers))
                    .disabled(isOnlyEnabledSlot(.qwertyNumbers))
                Toggle("#+=キー（記号）", isOn: binding(for: .qwertySymbols))
                    .disabled(isOnlyEnabledSlot(.qwertySymbols))
                Toggle("☆123キー（フリック）", isOn: binding(for: .flickStar123))
                    .disabled(isOnlyEnabledSlot(.flickStar123))
                Text(ClipboardLongPressSlotsSetting.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            slots.reload()
        }
    }

    private func binding(for slot: ClipboardLongPressSlot) -> Binding<Bool> {
        Binding(
            get: { slots.value.contains(slot) },
            set: { enabled in
                var updated = slots.value
                updated.set(slot, enabled: enabled)
                slots.value = updated
            }
        )
    }

    private func isOnlyEnabledSlot(_ slot: ClipboardLongPressSlot) -> Bool {
        slots.value.slots.count == 1 && slots.value.contains(slot)
    }
}
