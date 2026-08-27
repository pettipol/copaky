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

    func testLatinLanguageSeedUsesTheFirstLatinLanguageOnlyWhenTheOrderChanges() {
        XCTAssertEqual(
            ActiveKeyboardLanguagesSetting.latinLanguageSeed(
                languages: [.ja_JP, .it_IT, .en_US],
                lastSeededLanguages: nil
            ),
            .it_IT
        )
        XCTAssertEqual(
            ActiveKeyboardLanguagesSetting.latinLanguageSeed(
                languages: [.ja_JP, .en_US, .it_IT],
                lastSeededLanguages: [.ja_JP, .it_IT, .en_US]
            ),
            .en_US
        )
        XCTAssertNil(
            ActiveKeyboardLanguagesSetting.latinLanguageSeed(
                languages: [.ja_JP, .en_US, .it_IT],
                lastSeededLanguages: [.ja_JP, .en_US, .it_IT]
            )
        )
    }
}
