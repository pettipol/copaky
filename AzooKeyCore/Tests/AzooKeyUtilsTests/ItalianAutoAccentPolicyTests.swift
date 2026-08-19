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

    // Copaky: fail-closed — ANY declared textContentType disables auto-accent (re-review 2026-08-19).
    func testTextContentTypeGate() {
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsTextContentType(nil))
        for contentType: UITextContentType in [.name, .URL, .emailAddress, .password, .oneTimeCode, .creditCardNumber] {
            XCTAssertFalse(ItalianAutoAccentPolicy.allowsTextContentType(contentType), "\(contentType) must be blocked")
        }
    }

    // Copaky: the fail-closed oracle — valid plain words the bundled lexicon lacks must NOT be flagged,
    // genuine missing-accent misspellings must. Depends on the simulator's Italian dictionary.
    @MainActor func testSystemSpellCheckerOracle() throws {
        try XCTSkipUnless(
            UITextChecker.availableLanguages.contains(where: { $0.hasPrefix("it") }),
            "no Italian spell-check dictionary on this runtime"
        )
        // "cosi" is deliberately absent: the system dictionary accepts it (plural of "coso"), so the
        // oracle correctly refuses to turn it into "così" — a lost fix, never a wrong one.
        for word in ["perche", "piu", "citta", "puo"] {
            XCTAssertTrue(ItalianAutoAccentPolicy.systemFlagsAsMisspelledItalian(word), "\(word) must be flagged")
        }
        for word in ["Sara", "meta", "faro", "pero", "si", "da", "ciao", "perché"] {
            XCTAssertFalse(ItalianAutoAccentPolicy.systemFlagsAsMisspelledItalian(word), "\(word) must not be flagged")
        }
    }

    // Copaky: the second oracle stage — the system's own guesses must contain the exact fix.
    @MainActor func testSystemConfirmsAccentFix() throws {
        try XCTSkipUnless(
            UITextChecker.availableLanguages.contains(where: { $0.hasPrefix("it") }),
            "no Italian spell-check dictionary on this runtime"
        )
        XCTAssertTrue(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "perche", fix: "perché"))
        XCTAssertTrue(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "citta", fix: "città"))
        // Valid words and names are already accepted by the checker → first stage says no.
        XCTAssertFalse(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "Sara", fix: "Sarà"))
        XCTAssertFalse(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "meta", fix: "metà"))
        // A flagged word whose guesses do not contain our candidate must not be replaced.
        XCTAssertFalse(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "perche", fix: "città"))
    }
}

