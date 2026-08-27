import enum KanaKanjiConverterModule.KeyboardLanguage
@testable import AzooKeyUtils
import XCTest

final class ActiveKeyboardLanguagesSettingTests: XCTestCase {
    @MainActor
    func testLegacyTrueMigratesToJapaneseEnglishItalian() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(true, forKey: EnableItalianKeyboardLanguage.key)

        let languages = ActiveKeyboardLanguagesSetting.read(
            from: userDefaults,
            legacyDefault: false
        )

        XCTAssertEqual(languages, [.ja_JP, .en_US, .it_IT])
        XCTAssertEqual(
            userDefaults.stringArray(forKey: ActiveKeyboardLanguagesSetting.key),
            ["ja_JP", "en_US", "it_IT"]
        )
        XCTAssertEqual(userDefaults.object(forKey: EnableItalianKeyboardLanguage.key) as? Bool, true)
    }

    @MainActor
    func testLegacyFalseMigratesToJapaneseEnglish() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(false, forKey: EnableItalianKeyboardLanguage.key)

        let languages = ActiveKeyboardLanguagesSetting.read(
            from: userDefaults,
            legacyDefault: true
        )

        XCTAssertEqual(languages, [.ja_JP, .en_US])
        XCTAssertEqual(
            userDefaults.stringArray(forKey: ActiveKeyboardLanguagesSetting.key),
            ["ja_JP", "en_US"]
        )
        XCTAssertEqual(userDefaults.object(forKey: EnableItalianKeyboardLanguage.key) as? Bool, false)
    }

    @MainActor
    func testMissingKeysUseLegacyDefaultAndBackfillBothRepresentations() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let languages = ActiveKeyboardLanguagesSetting.read(
            from: userDefaults,
            legacyDefault: true
        )

        XCTAssertEqual(languages, [.ja_JP, .en_US, .it_IT])
        XCTAssertEqual(
            userDefaults.stringArray(forKey: ActiveKeyboardLanguagesSetting.key),
            ["ja_JP", "en_US", "it_IT"]
        )
        XCTAssertEqual(userDefaults.object(forKey: EnableItalianKeyboardLanguage.key) as? Bool, true)
    }

    @MainActor
    func testStoredListWithoutLegacyBooleanBackfillsTheBoolean() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            ["ja_JP", "it_IT", "en_US"],
            forKey: ActiveKeyboardLanguagesSetting.key
        )

        let languages = ActiveKeyboardLanguagesSetting.read(
            from: userDefaults,
            legacyDefault: false
        )

        XCTAssertEqual(languages, [.ja_JP, .it_IT, .en_US])
        XCTAssertEqual(userDefaults.object(forKey: EnableItalianKeyboardLanguage.key) as? Bool, true)
    }

    @MainActor
    func testOrderedListWritesItalianStateBackToLegacyBoolean() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        ActiveKeyboardLanguagesSetting.write([.ja_JP, .it_IT, .en_US], to: userDefaults)
        XCTAssertEqual(userDefaults.object(forKey: EnableItalianKeyboardLanguage.key) as? Bool, true)

        ActiveKeyboardLanguagesSetting.write([.ja_JP, .en_US], to: userDefaults)
        XCTAssertEqual(userDefaults.object(forKey: EnableItalianKeyboardLanguage.key) as? Bool, false)
    }

    @MainActor
    func testLaterLegacyWriteUpdatesAnExistingOrderedList() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        ActiveKeyboardLanguagesSetting.write([.ja_JP, .en_US], to: userDefaults)

        userDefaults.set(true, forKey: EnableItalianKeyboardLanguage.key)
        let languages = ActiveKeyboardLanguagesSetting.read(
            from: userDefaults,
            legacyDefault: false
        )

        XCTAssertEqual(languages, [.ja_JP, .en_US, .it_IT])
        XCTAssertEqual(
            userDefaults.stringArray(forKey: ActiveKeyboardLanguagesSetting.key),
            ["ja_JP", "en_US", "it_IT"]
        )

        userDefaults.set(false, forKey: EnableItalianKeyboardLanguage.key)
        let disabledLanguages = ActiveKeyboardLanguagesSetting.read(
            from: userDefaults,
            legacyDefault: true
        )

        XCTAssertEqual(disabledLanguages, [.ja_JP, .en_US])
        XCTAssertEqual(
            userDefaults.stringArray(forKey: ActiveKeyboardLanguagesSetting.key),
            ["ja_JP", "en_US"]
        )
    }

    func testNormalizationPinsJapaneseAndKeepsTheLatinOrder() {
        XCTAssertEqual(
            ActiveKeyboardLanguagesPolicy.normalized([.it_IT, .ja_JP, .it_IT]),
            [.ja_JP, .it_IT, .en_US]
        )
        XCTAssertEqual(
            ActiveKeyboardLanguagesPolicy.normalized([.en_US, .ja_JP, .none]),
            [.ja_JP, .en_US]
        )
    }

    private func makeUserDefaults() throws -> (UserDefaults, String) {
        let suiteName = "ActiveKeyboardLanguagesSettingTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
