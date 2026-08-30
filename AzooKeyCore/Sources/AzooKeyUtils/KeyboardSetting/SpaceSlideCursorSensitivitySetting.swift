//
//  SpaceSlideCursorSensitivitySetting.swift
//  AzooKeyUtils
//

import Foundation
import KeyboardViews
import SwiftUI

extension SpaceSlideCursorSensitivity: Savable {
    typealias SaveValue = String

    var saveValue: String {
        rawValue
    }

    static func get(_ value: Any) -> Self? {
        guard let rawValue = value as? String else {
            return nil
        }
        return Self(rawValue: rawValue)
    }
}

public struct SpaceSlideCursorSensitivitySetting: KeyboardSettingKey, StoredInUserDefault {
    public static let title: LocalizedStringKey = "スライド感度"
    public static let explanation: LocalizedStringKey = "スペースバーをスライドしたときに、カーソルが1文字動くまでの距離を調整します。"
    public static let defaultValue: SpaceSlideCursorSensitivity = .medium
    public static let key = "space_slide_cursor_sensitivity"

    @MainActor static func get() -> SpaceSlideCursorSensitivity? {
        guard let value = SharedStore.userDefaults.object(forKey: key) else {
            return nil
        }
        return SpaceSlideCursorSensitivity.get(value)
    }

    @MainActor static func set(newValue: SpaceSlideCursorSensitivity) {
        SharedStore.userDefaults.set(newValue.saveValue, forKey: key)
    }

    @MainActor public static var value: SpaceSlideCursorSensitivity {
        get {
            get() ?? defaultValue
        }
        set {
            set(newValue: newValue)
        }
    }
}

public extension KeyboardSettingKey where Self == SpaceSlideCursorSensitivitySetting {
    static var spaceSlideCursorSensitivity: Self { .init() }
}
