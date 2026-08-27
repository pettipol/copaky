//
//  ActiveKeyboardLanguagesSetting.swift
//  AzooKeyUtils
//

import Foundation
import enum KanaKanjiConverterModule.KeyboardLanguage
import SwiftUI

struct ActiveKeyboardLanguagesResolution: Equatable, Sendable {
    let languages: [KeyboardLanguage]
    let legacyItalianEnabled: Bool
}

enum ActiveKeyboardLanguagesPolicy {
    static func normalized(_ languages: [KeyboardLanguage]) -> [KeyboardLanguage] {
        var latinLanguages: [KeyboardLanguage] = []
        for language in languages where language == .en_US || language == .it_IT {
            if !latinLanguages.contains(language) {
                latinLanguages.append(language)
            }
        }
        if !latinLanguages.contains(.en_US) {
            latinLanguages.append(.en_US)
        }
        return [.ja_JP] + latinLanguages
    }

    static func updatingItalian(in languages: [KeyboardLanguage], enabled: Bool) -> [KeyboardLanguage] {
        var result = normalized(languages)
        if enabled {
            if !result.contains(.it_IT) {
                result.append(.it_IT)
            }
        } else {
            result.removeAll { $0 == .it_IT }
        }
        return normalized(result)
    }

    static func resolve(
        storedRawValues: [String]?,
        storedLegacyItalianEnabled: Bool?,
        legacyDefault: Bool
    ) -> ActiveKeyboardLanguagesResolution {
        guard let storedRawValues else {
            let enabled = storedLegacyItalianEnabled ?? legacyDefault
            let languages = updatingItalian(in: [.ja_JP, .en_US], enabled: enabled)
            return .init(languages: languages, legacyItalianEnabled: enabled)
        }

        var languages = normalized(storedRawValues.compactMap { KeyboardLanguage(rawValue: $0) })
        // Treat a stored membership mismatch as a later legacy write. The editor activates IT in
        // canonical EN→IT order, then performs any independent reorder with the boolean unchanged.
        if let storedLegacyItalianEnabled,
           storedLegacyItalianEnabled != languages.contains(.it_IT) {
            languages = updatingItalian(in: languages, enabled: storedLegacyItalianEnabled)
        }
        return .init(
            languages: languages,
            legacyItalianEnabled: languages.contains(.it_IT)
        )
    }

    static func firstLatinLanguage(in languages: [KeyboardLanguage]) -> KeyboardLanguage {
        normalized(languages).first(where: { $0.usesLatinScript }) ?? .en_US
    }
}

public struct ActiveKeyboardLanguagesSetting: KeyboardSettingKey, StoredInUserDefault {
    public static let title: LocalizedStringKey = "使用する言語"
    public static let explanation: LocalizedStringKey = "日本語は先頭に固定され、英語は常に有効です。イタリア語を有効にすると、英語との順番を並べ替えられます。"
    public static var defaultValue: [KeyboardLanguage] {
        ActiveKeyboardLanguagesPolicy.updatingItalian(
            in: [.ja_JP, .en_US],
            enabled: EnableItalianKeyboardLanguage.defaultValue
        )
    }
    public static let key = "active_keyboard_languages_order"

    @MainActor
    static func read(from userDefaults: UserDefaults, legacyDefault: Bool) -> [KeyboardLanguage] {
        let storedRawValues: [String]? = if userDefaults.object(forKey: key) == nil {
            nil
        } else {
            userDefaults.stringArray(forKey: key) ?? []
        }
        let storedLegacyItalianEnabled = userDefaults.object(
            forKey: EnableItalianKeyboardLanguage.key
        ) as? Bool
        let resolution = ActiveKeyboardLanguagesPolicy.resolve(
            storedRawValues: storedRawValues,
            storedLegacyItalianEnabled: storedLegacyItalianEnabled,
            legacyDefault: legacyDefault
        )
        if storedLegacyItalianEnabled != resolution.legacyItalianEnabled {
            userDefaults.set(
                resolution.legacyItalianEnabled,
                forKey: EnableItalianKeyboardLanguage.key
            )
        }
        let resolvedRawValues = resolution.languages.map(\.rawValue)
        if storedRawValues != resolvedRawValues {
            userDefaults.set(resolvedRawValues, forKey: key)
        }
        return resolution.languages
    }

    @MainActor
    static func write(_ languages: [KeyboardLanguage], to userDefaults: UserDefaults) {
        let normalized = ActiveKeyboardLanguagesPolicy.normalized(languages)
        // Store raw strings as a native plist array so the shared preference remains inspectable.
        userDefaults.set(normalized.contains(.it_IT), forKey: EnableItalianKeyboardLanguage.key)
        userDefaults.set(normalized.map(\.rawValue), forKey: key)
    }

    @MainActor
    static func setItalianEnabled(_ enabled: Bool, in userDefaults: UserDefaults) {
        let current = read(
            from: userDefaults,
            legacyDefault: EnableItalianKeyboardLanguage.defaultValue
        )
        write(
            ActiveKeyboardLanguagesPolicy.updatingItalian(in: current, enabled: enabled),
            to: userDefaults
        )
    }

    @MainActor public static var value: [KeyboardLanguage] {
        get {
            read(
                from: SharedStore.userDefaults,
                legacyDefault: EnableItalianKeyboardLanguage.defaultValue
            )
        }
        set {
            write(newValue, to: SharedStore.userDefaults)
        }
    }

    public static func latinLanguageSeed(
        languages: [KeyboardLanguage],
        lastSeededLanguages: [KeyboardLanguage]?
    ) -> KeyboardLanguage? {
        let normalized = ActiveKeyboardLanguagesPolicy.normalized(languages)
        guard normalized != lastSeededLanguages else {
            return nil
        }
        return ActiveKeyboardLanguagesPolicy.firstLatinLanguage(in: normalized)
    }
}

public extension KeyboardSettingKey where Self == ActiveKeyboardLanguagesSetting {
    static var activeKeyboardLanguages: Self { .init() }
}
