import AzooKeyUtils
import UIKit
import XCTest

// Copaky: cover the pure safety gates used before the converter's accent-fix lookup.
// Copaky: 変換器を呼ぶ前の安全判定を純粋な単体テストで確認する。
final class ItalianAutoAccentPolicyTests: XCTestCase {
    func testSettingContract() {
        XCTAssertTrue(ItalianAutoAccentOnSpace.defaultValue)
        XCTAssertEqual(ItalianAutoAccentOnSpace.key, "italian_auto_accent_on_space")
    }

    func testSentenceStartDetection() {
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: nil))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: ""))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "   "))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao. "))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao!\n"))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao? "))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao… "))
        XCTAssertFalse(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao "))
    }

    func testCapitalizedWordIsLimitedToSentenceStart() {
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsCapitalization(of: "Sara", documentContextBeforeInput: nil))
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsCapitalization(of: "Sara", documentContextBeforeInput: "Ciao. "))
        XCTAssertFalse(ItalianAutoAccentPolicy.allowsCapitalization(of: "Sara", documentContextBeforeInput: "Ciao "))
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsCapitalization(of: "sara", documentContextBeforeInput: "Ciao "))
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsCapitalization(of: "SARA", documentContextBeforeInput: "Ciao "))
    }

    func testKeyboardTypeGate() {
        for keyboardType: UIKeyboardType in [
            .URL, .emailAddress, .twitter, .namePhonePad, .asciiCapableNumberPad,
            .numberPad, .phonePad, .decimalPad,
        ] {
            XCTAssertFalse(ItalianAutoAccentPolicy.allowsKeyboardType(keyboardType), "Expected \(keyboardType) to be blocked")
        }
        for keyboardType: UIKeyboardType in [.default, .asciiCapable, .numbersAndPunctuation, .webSearch] {
            XCTAssertTrue(ItalianAutoAccentPolicy.allowsKeyboardType(keyboardType), "Expected \(keyboardType) to be allowed")
        }
    }
}
