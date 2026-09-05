//
//  ClipboardLongPressSlotsSettingView.swift
//  MainApp
//

import AzooKeyUtils
import KeyboardViews
import SwiftUI

// Copaky [G-07]: advanced clipboard shortcut choices live off the essential settings list.
struct ClipboardLongPressSlotsSettingView: View {
    @State private var slots: SettingUpdater<ClipboardLongPressSlotsSetting>

    @MainActor init() {
        self._slots = .init(initialValue: .init())
    }

    var body: some View {
        Form {
            Section {
                Toggle("123キー（文字）", isOn: binding(for: .qwertyNumbers))
                    .disabled(isOnlyEnabledSlot(.qwertyNumbers))
                Toggle("#+=キー（記号）", isOn: binding(for: .qwertySymbols))
                    .disabled(isOnlyEnabledSlot(.qwertySymbols))
                Toggle("☆123キー（フリック）", isOn: binding(for: .flickStar123))
                    .disabled(isOnlyEnabledSlot(.flickStar123))
            } header: {
                Text(ClipboardLongPressSlotsSetting.title)
            } footer: {
                Text(ClipboardLongPressSlotsSetting.explanation)
            }
        }
        .navigationTitle("詳しい設定")
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
