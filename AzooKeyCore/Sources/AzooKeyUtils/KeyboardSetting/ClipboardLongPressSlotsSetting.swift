//
//  ClipboardLongPressSlotsSetting.swift
//  AzooKeyUtils
//

import Foundation
import KeyboardViews
import SwiftUI

extension ClipboardLongPressSlots: Savable {
    typealias SaveValue = Data

    var saveValue: Data {
        let rawValues = ClipboardLongPressSlot.allCases
            .filter { contains($0) }
            .map(\.rawValue)
        return (try? JSONEncoder().encode(rawValues)) ?? Data()
    }

    static func get(_ value: Any) -> Self? {
        guard let data = value as? Data,
              let rawValues = try? JSONDecoder().decode([String].self, from: data),
              !rawValues.isEmpty else {
            return nil
        }
        let decoded = rawValues.compactMap(ClipboardLongPressSlot.init(rawValue:))
        // Unknown raw values fail closed instead of silently enabling a different site.
        // 未知のraw値は別スロットを有効化せず、既定値へフォールバックさせる。
        guard decoded.count == rawValues.count, !decoded.isEmpty else {
            return nil
        }
        return .init(slots: Set(decoded))
    }
}

public struct ClipboardLongPressSlotsSetting: KeyboardSettingKey, StoredInUserDefault {
    public static let title: LocalizedStringKey = "長押しで履歴を開くキー"
    public static let explanation: LocalizedStringKey = "オンにしたキーを長押しするとクリップボード履歴が開きます。少なくとも1つのキーを選んでください。"
    public static let defaultValue = ClipboardLongPressSlots(slots: [.qwertyNumbers])
    public static let key = "clipboard_long_press_slots"

    @MainActor static func get() -> ClipboardLongPressSlots? {
        guard let value = SharedStore.userDefaults.object(forKey: key) else {
            return nil
        }
        return ClipboardLongPressSlots.get(value)
    }

    @MainActor static func set(newValue: ClipboardLongPressSlots) {
        SharedStore.userDefaults.set(newValue.saveValue, forKey: key)
    }

    @MainActor public static var value: ClipboardLongPressSlots {
        get {
            get() ?? defaultValue
        }
        set {
            set(newValue: newValue)
        }
    }
}

public extension KeyboardSettingKey where Self == ClipboardLongPressSlotsSetting {
    static var clipboardLongPressSlots: Self { .init() }
}
