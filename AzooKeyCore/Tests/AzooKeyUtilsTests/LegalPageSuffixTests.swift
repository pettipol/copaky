import AzooKeyUtils
import XCTest

// Copaky [G-26]: legal URLs follow only the user's first preferred language.
final class LegalPageSuffixTests: XCTestCase {
    func testLocalizedLegalPageSuffix() {
        XCTAssertEqual(legalPageSuffix(preferredLanguages: ["it-IT"]), ".it")
        XCTAssertEqual(legalPageSuffix(preferredLanguages: ["it"]), ".it")
        XCTAssertEqual(legalPageSuffix(preferredLanguages: ["ja-JP"]), ".ja")
        XCTAssertEqual(legalPageSuffix(preferredLanguages: ["en-US"]), "")
        XCTAssertEqual(legalPageSuffix(preferredLanguages: ["fr-FR"]), "")
        XCTAssertEqual(legalPageSuffix(preferredLanguages: []), "")
    }

    func testOnlyFirstPreferredLanguageSelectsThePage() {
        XCTAssertEqual(legalPageSuffix(preferredLanguages: ["en-US", "it-IT"]), "")
    }
}
