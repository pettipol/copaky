import AzooKeyUtils
import XCTest

final class EnableItalianKeyboardLanguageTests: XCTestCase {
    func testItalianFirstPreferredLanguageIsRecognized() {
        for language in ["it", "it-IT", "it_CH"] {
            XCTAssertTrue(
                EnableItalianKeyboardLanguage.isItalianSystemLanguage(preferredLanguages: [language]),
                "Expected \(language) to be recognized as Italian"
            )
        }
    }

    func testOnlyFirstPreferredLanguageDeterminesTheResult() {
        XCTAssertFalse(EnableItalianKeyboardLanguage.isItalianSystemLanguage(preferredLanguages: []))
        XCTAssertFalse(EnableItalianKeyboardLanguage.isItalianSystemLanguage(preferredLanguages: ["en-IT"]))
        XCTAssertFalse(EnableItalianKeyboardLanguage.isItalianSystemLanguage(preferredLanguages: ["en-US", "it-IT"]))
    }

    // Copaky: a first load always seeds; unchanged settings preserve a later manual language choice.
    // Copaky: 初回は必ず設定し、設定が同じなら後の手動選択を保持する。
    func testLatinLanguageSeedOnlyChangesWhenSettingChanges() {
        XCTAssertEqual(EnableItalianKeyboardLanguage.latinLanguageSeed(enabled: true, lastSeeded: nil), .it_IT)
        XCTAssertEqual(EnableItalianKeyboardLanguage.latinLanguageSeed(enabled: false, lastSeeded: nil), .en_US)
        XCTAssertNil(EnableItalianKeyboardLanguage.latinLanguageSeed(enabled: true, lastSeeded: true))
        XCTAssertNil(EnableItalianKeyboardLanguage.latinLanguageSeed(enabled: false, lastSeeded: false))
        XCTAssertEqual(EnableItalianKeyboardLanguage.latinLanguageSeed(enabled: true, lastSeeded: false), .it_IT)
        XCTAssertEqual(EnableItalianKeyboardLanguage.latinLanguageSeed(enabled: false, lastSeeded: true), .en_US)
    }
}
