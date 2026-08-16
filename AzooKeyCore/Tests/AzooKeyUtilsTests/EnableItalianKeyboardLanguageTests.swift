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
}
